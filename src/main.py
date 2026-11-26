"""API de tareas persistidas en RDS MySQL.

Las credenciales salen de Secrets Manager en cada conexión. La versión
desplegada se lee de APP_VERSION. Los fallos de base y las tareas creadas
se publican en CloudWatch (namespace TodoList).
"""

import json
import os
from datetime import datetime, timezone

import boto3
import pymysql
from flask import Flask, jsonify, request

app = Flask(__name__)

METRIC_NAMESPACE = "TodoList"


def app_version():
    return os.environ.get("APP_VERSION", "dev")


def put_metric(name, value=1):
    """Publica un conteo en CloudWatch. Un fallo aquí no tumba la API."""
    try:
        client = boto3.client(
            "cloudwatch",
            region_name=os.environ.get("AWS_REGION", "us-east-1"),
        )
        client.put_metric_data(
            Namespace=METRIC_NAMESPACE,
            MetricData=[
                {
                    "MetricName": name,
                    "Value": value,
                    "Unit": "Count",
                }
            ],
        )
    except Exception:
        return


def load_db_config():
    secret_id = os.environ["SECRET_ID"]
    client = boto3.client(
        "secretsmanager",
        region_name=os.environ.get("AWS_REGION", "us-east-1"),
    )
    raw = client.get_secret_value(SecretId=secret_id)["SecretString"]
    return json.loads(raw)


def connect():
    config = load_db_config()
    return pymysql.connect(
        host=config["host"],
        port=int(config["port"]),
        user=config["username"],
        password=config["password"],
        database=config["dbname"],
        connect_timeout=5,
        autocommit=True,
        cursorclass=pymysql.cursors.DictCursor,
    )


def ensure_schema(conn):
    with conn.cursor() as cur:
        cur.execute(
            """
            CREATE TABLE IF NOT EXISTS tasks (
                id INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
                title VARCHAR(255) NOT NULL,
                done TINYINT(1) NOT NULL DEFAULT 0
            )
            """
        )


def with_db(fn):
    """Abre conexión, asegura la tabla y cuenta un RDSErrors si algo falla."""
    try:
        conn = connect()
        try:
            ensure_schema(conn)
            return fn(conn)
        finally:
            conn.close()
    except Exception:
        put_metric("RDSErrors")
        raise


def task_from_row(row):
    return {
        "id": row["id"],
        "title": row["title"],
        "done": bool(row["done"]),
    }


@app.get("/tasks")
def list_tasks():
    try:
        def query(conn):
            with conn.cursor() as cur:
                cur.execute("SELECT id, title, done FROM tasks ORDER BY id")
                return [task_from_row(row) for row in cur.fetchall()]

        return jsonify(with_db(query))
    except Exception:
        return jsonify({"error": "database error"}), 503


@app.post("/tasks")
def create_task():
    payload = request.get_json(silent=True) or {}
    title = (payload.get("title") or "").strip()
    if not title:
        return jsonify({"error": "title is required"}), 400

    done = bool(payload.get("done", False))

    try:
        def insert(conn):
            with conn.cursor() as cur:
                cur.execute(
                    "INSERT INTO tasks (title, done) VALUES (%s, %s)",
                    (title, int(done)),
                )
                return {
                    "id": cur.lastrowid,
                    "title": title,
                    "done": done,
                }

        task = with_db(insert)
    except Exception:
        return jsonify({"error": "database error"}), 503

    put_metric("TasksCreated")
    return jsonify(task), 201


@app.get("/version")
def version():
    return jsonify({"version": app_version()})


@app.get("/health")
def health():
    status = "OK"
    try:
        def ping(conn):
            with conn.cursor() as cur:
                cur.execute("SELECT 1")

        with_db(ping)
    except Exception:
        status = "FAIL"

    return jsonify(
        {
            "status": status,
            "version": app_version(),
            "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        }
    )


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8000)
