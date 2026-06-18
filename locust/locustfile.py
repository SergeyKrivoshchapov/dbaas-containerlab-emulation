import time
import random
import psycopg2
from locust import User, task, between, events


class PgUser(User):
    wait_time = between(0.5, 2)

    def on_start(self):
        self.connect()
        self.init_db()

    def connect(self):
        try:
            self.write_conn = psycopg2.connect(
                host="127.0.0.1",
                port=5432,
                user="postgres",
                password="mypassword",
                dbname="postgres",
            )
            self.write_conn.autocommit = True
        except Exception:
            self.write_conn = None

        try:
            self.read_conn = psycopg2.connect(
                host="127.0.0.1",
                port=5433,
                user="postgres",
                password="mypassword",
                dbname="postgres",
            )
            self.read_conn.autocommit = True
        except Exception:
            self.read_conn = None

    def init_db(self):
        if self.write_conn:
            try:
                cur = self.write_conn.cursor()
                cur.execute("""
                    CREATE TABLE IF NOT EXISTS locust_test (
                        id SERIAL PRIMARY KEY,
                        name TEXT,
                        value INTEGER,
                        created_at TIMESTAMP DEFAULT NOW()
                    )
                """)
                cur.close()
            except Exception:
                pass

    def on_stop(self):
        if self.write_conn:
            try:
                self.write_conn.close()
            except Exception:
                pass
        if self.read_conn:
            try:
                self.read_conn.close()
            except Exception:
                pass

    @task(3)
    def read_data(self):
        start = time.time()
        try:
            if not self.read_conn or self.read_conn.closed:
                self.read_conn = psycopg2.connect(
                    host="127.0.0.1",
                    port=5433,
                    user="postgres",
                    password="mypassword",
                    dbname="postgres",
                )
                self.read_conn.autocommit = True
            cur = self.read_conn.cursor()
            cur.execute("SELECT COUNT(*) FROM locust_test")
            cur.fetchone()
            cur.close()
            success = True
        except Exception:
            success = False
        events.request.fire(
            request_type="READ",
            name="select_count",
            response_time=(time.time() - start) * 1000,
            response_length=0,
            success=success,
        )

    @task(2)
    def write_data(self):
        start = time.time()
        try:
            if not self.write_conn or self.write_conn.closed:
                self.write_conn = psycopg2.connect(
                    host="127.0.0.1",
                    port=5432,
                    user="postgres",
                    password="mypassword",
                    dbname="postgres",
                )
                self.write_conn.autocommit = True
            cur = self.write_conn.cursor()
            cur.execute(
                "INSERT INTO locust_test (name, value) VALUES (%s, %s)",
                (f"user_{random.randint(1, 10000)}", random.randint(1, 1000)),
            )
            cur.close()
            success = True
        except Exception:
            success = False
        events.request.fire(
            request_type="WRITE",
            name="insert",
            response_time=(time.time() - start) * 1000,
            response_length=0,
            success=success,
        )

    @task(1)
    def mixed_operation(self):
        start = time.time()
        success = True
        try:
            if not self.read_conn or self.read_conn.closed:
                self.read_conn = psycopg2.connect(
                    host="127.0.0.1",
                    port=5433,
                    user="postgres",
                    password="mypassword",
                    dbname="postgres",
                )
                self.read_conn.autocommit = True
            cur = self.read_conn.cursor()
            cur.execute("SELECT COUNT(*) FROM locust_test WHERE value > %s", (500,))
            cur.fetchone()
            cur.close()

            if not self.write_conn or self.write_conn.closed:
                self.write_conn = psycopg2.connect(
                    host="127.0.0.1",
                    port=5432,
                    user="postgres",
                    password="mypassword",
                    dbname="postgres",
                )
                self.write_conn.autocommit = True
            cur = self.write_conn.cursor()
            cur.execute(
                "UPDATE locust_test SET value = value + 1 WHERE id = %s",
                (random.randint(1, 100),),
            )
            cur.close()
        except Exception:
            success = False
        events.request.fire(
            request_type="MIXED",
            name="read_write",
            response_time=(time.time() - start) * 1000,
            response_length=0,
            success=success,
        )
