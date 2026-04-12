"""
lambda/function.py
==================
AWS Lambda function: Generic Market Data Processor
Project : aws-vpc-lambda-rds-fintech
Runtime : Python 3.12
Layer   : Klayers-p312-psycopg2-binary

Description
-----------
if it does not exist, inserts sample market stock
records, and queries the latest 10 records.

Environment Variables (set in lambda.tf)
-----------------------------------------
  DB_HOST     — RDS endpoint hostname
  DB_PORT     — 5432
  DB_NAME     — Database name
  DB_USER     — Master username
  DB_PASSWORD — Master password

Returns
-------
HTTP-style JSON response with statusCode, market data array,
aggregate metrics, and processing timestamp.
"""

import json
import logging
import os
from datetime import datetime, timezone
from decimal import Decimal

import psycopg2
from psycopg2.extras import RealDictCursor

# ─────────────────────────────────────────────
# Logging
# ─────────────────────────────────────────────
logger = logging.getLogger()
logger.setLevel(logging.INFO)


# ─────────────────────────────────────────────
# Database helpers
# ─────────────────────────────────────────────

def _get_connection():
    """
    Open and return a new psycopg2 connection using env-var credentials.
    Raises a RuntimeError if any required variable is missing.
    """
    required = ("DB_HOST", "DB_PORT", "DB_NAME", "DB_USER", "DB_PASSWORD")
    missing = [k for k in required if not os.environ.get(k)]
    if missing:
        raise RuntimeError(f"Missing required environment variables: {missing}")

    return psycopg2.connect(
        host=os.environ["DB_HOST"],
        port=int(os.environ["DB_PORT"]),
        dbname=os.environ["DB_NAME"],
        user=os.environ["DB_USER"],
        password=os.environ["DB_PASSWORD"],
        connect_timeout=10,
        sslmode="require",       # Enforce TLS in transit
    )


def _ensure_table(cursor):
    """
    Create the market_data table (and index) if they do not already exist.
    Schema
    ------
    id        SERIAL PRIMARY KEY
    symbol    VARCHAR(10)       — Stock ticker (e.g. EMAAR)
    price     DECIMAL(10,2)     — Last traded price (AED)
    volume    INTEGER           — Number of shares traded
    timestamp TIMESTAMP         — Trade timestamp (UTC)
    """
    cursor.execute(
        """
        CREATE TABLE IF NOT EXISTS market_data (
            id        SERIAL        PRIMARY KEY,
            symbol    VARCHAR(10)   NOT NULL,
            price     DECIMAL(10,2) NOT NULL,
            volume    INTEGER       NOT NULL,
            timestamp TIMESTAMP     NOT NULL DEFAULT NOW()
        );

        CREATE INDEX IF NOT EXISTS idx_market_data_symbol
            ON market_data (symbol);

        CREATE INDEX IF NOT EXISTS idx_market_data_timestamp
            ON market_data (timestamp DESC);
        """
    )
    logger.info("market_data table verified / created.")


def _insert_sample_data(cursor):
    """
    Insert a batch of representative sample stock records.
    In production you would replace this with real feed data.
    Data is keyed on (symbol, timestamp) to avoid duplicate inserts
    within the same Lambda invocation.
    """
    now_utc = datetime.now(tz=timezone.utc).replace(tzinfo=None)

    # ── Sample Stock Data (Reference prices) ──────────────
    stocks = [
        # (symbol,   price USD, volume)
        ("TECH_A",  Decimal("150.25"), 15_000_000),   # Generic Tech Company
        ("FIN_B",   Decimal("45.82"),   8_500_000),   # Generic Financial Bank
        ("HLTH_C",  Decimal("120.45"), 12_000_000),   # Generic Healthcare Corp
        ("ENGY_D",  Decimal("75.34"),   9_800_000),   # Generic Energy Provider
        ("LOGI_E",  Decimal("30.91"),   5_600_000),   # Generic Logistics Firm
    ]

    cursor.executemany(
        """
        INSERT INTO market_data (symbol, price, volume, timestamp)
        VALUES (%s, %s, %s, %s)
        """,
        [(s[0], s[1], s[2], now_utc) for s in stocks],
    )
    logger.info("Inserted %d sample stock records.", len(stocks))
    return len(stocks)


def _query_latest(cursor, limit: int = 10) -> list[dict]:
    """
    Fetch the most recent *limit* rows ordered by timestamp descending.
    Returns a list of dicts with JSON-serialisable values.
    """
    cursor.execute(
        """
        SELECT id, symbol, price, volume,
               TO_CHAR(timestamp, 'YYYY-MM-DD"T"HH24:MI:SS"Z"') AS timestamp
        FROM   market_data
        ORDER  BY timestamp DESC, id DESC
        LIMIT  %s
        """,
        (limit,),
    )
    rows = cursor.fetchall()

    # Convert Decimal → float for JSON serialisation
    return [
        {
            "id":        row["id"],
            "symbol":    row["symbol"],
            "price":     float(row["price"]),
            "volume":    row["volume"],
            "timestamp": row["timestamp"],
        }
        for row in rows
    ]


# ─────────────────────────────────────────────
# Lambda Entry Point
# ─────────────────────────────────────────────

def lambda_handler(event: dict, context) -> dict:
    """
    Main handler invoked by AWS Lambda.

    Parameters
    ----------
    event   : dict   — Event payload (unused; extend for API GW integration)
    context : object — Lambda runtime context

    Returns
    -------
    dict — AWS-compatible response with statusCode, headers, and JSON body.
    """
    logger.info("Lambda invoked. RequestId: %s", context.aws_request_id)

    conn = None
    try:
        # ── 1. Connect to PostgreSQL ──────────────────────────────────────
        logger.info("Connecting to RDS at %s …", os.environ.get("DB_HOST"))
        conn = _get_connection()
        conn.autocommit = False

        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            # ── 2. Ensure schema exists ───────────────────────────────────
            _ensure_table(cur)

            # ── 3. Insert sample data ─────────────────────────────────
            inserted_count = _insert_sample_data(cur)

            # ── 4. Query latest records ───────────────────────────────────
            market_data = _query_latest(cur, limit=10)

        conn.commit()
        logger.info("Transaction committed. Rows returned: %d", len(market_data))

        # ── 5. Compute aggregate metrics ──────────────────────────────────
        total_volume = sum(row["volume"] for row in market_data)

        # ── 6. Build response ─────────────────────────────────────────────
        body = {
            "message":            "Market data processed successfully",
            "records_inserted":   inserted_count,
            "records_returned":   len(market_data),
            "total_volume":       total_volume,
            "market_data":        market_data,
            "processed_at":       datetime.now(tz=timezone.utc).strftime(
                                       "%Y-%m-%dT%H:%M:%SZ"
                                  ),
            "request_id":         context.aws_request_id,
        }

        return {
            "statusCode": 200,
            "headers": {
                "Content-Type":                "application/json",
                "X-Request-Id":                context.aws_request_id,
                "X-Powered-By":                "aws-vpc-lambda-rds-fintech",
            },
            "body": json.dumps(body, default=str),
        }

    except psycopg2.OperationalError as exc:
        # Connection-level failures (wrong host, SG blocked, timeout)
        logger.error("Database connection error: %s", exc, exc_info=True)
        if conn:
            conn.rollback()
        return _error_response(503, "Database connection failed", str(exc))

    except psycopg2.DatabaseError as exc:
        # SQL-level failures (bad query, constraint violation, etc.)
        logger.error("Database error: %s", exc, exc_info=True)
        if conn:
            conn.rollback()
        return _error_response(500, "Database error", str(exc))

    except Exception as exc:  # pylint: disable=broad-except
        logger.error("Unexpected error: %s", exc, exc_info=True)
        if conn:
            conn.rollback()
        return _error_response(500, "Internal server error", str(exc))

    finally:
        if conn and not conn.closed:
            conn.close()
            logger.info("Database connection closed.")


def _error_response(status_code: int, message: str, detail: str = "") -> dict:
    """Build a uniform error response body."""
    body = {
        "error":   message,
        "detail":  detail,
        "status":  status_code,
    }
    return {
        "statusCode": status_code,
        "headers":    {"Content-Type": "application/json"},
        "body":       json.dumps(body),
    }
