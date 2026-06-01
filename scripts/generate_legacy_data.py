"""Genera un dataset legacy sintético con datos sucios para la PoC Data Mesh.

Salida por defecto:
    data/legacy/raw_legacy_transactions.csv

La intención es simular un Data Lake monolítico heredado con problemas típicos:
- divisas mezcladas
- valores nulos
- formatos de fecha inconsistentes o inválidos
- presencia de PII (customer_email, credit_card)
"""

from __future__ import annotations

import argparse
import csv
import random
from datetime import datetime, timedelta
from pathlib import Path


DEFAULT_ROWS = 1500
DEFAULT_OUTPUT = Path("data/legacy/raw_legacy_transactions.csv")
RANDOM_SEED = 42

TERRITORIES = ["ES", "PT", "FR", "DE", "IT", "UK"]
PAYMENT_METHODS = ["card", "wire", "paypal", "cash"]
PRODUCT_CATEGORIES = [
    "electronics",
    "home",
    "sports",
    "fashion",
    "books",
    "groceries",
]
SALES_CHANNELS = ["web", "mobile", "store", "partner"]
CUSTOMER_DOMAINS = ["example.com", "legacy.local", "mail.net", "retail.org"]
VALID_CURRENCIES = ["EUR", "USD", "GBP"]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Generar CSV legacy sintético")
    parser.add_argument(
        "--rows",
        type=int,
        default=DEFAULT_ROWS,
        help=f"Cantidad de filas a generar (por defecto: {DEFAULT_ROWS})",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=DEFAULT_OUTPUT,
        help=f"Ruta de salida del CSV (por defecto: {DEFAULT_OUTPUT})",
    )
    return parser.parse_args()


def random_date(base_date: datetime) -> datetime:
    return base_date + timedelta(days=random.randint(0, 720), hours=random.randint(0, 23))


def format_mixed_date(dt: datetime) -> str:
    valid_formats = [
        dt.strftime("%Y-%m-%d"),
        dt.strftime("%d/%m/%Y"),
        dt.strftime("%Y/%m/%d %H:%M:%S"),
        dt.strftime("%d-%m-%Y %H:%M"),
    ]
    invalid_formats = [
        f"{dt.year}-13-{dt.day:02d}",
        f"{dt.day:02d}/{dt.month:02d}/{str(dt.year)[2:]}",
        "not_available",
        "2023-02-30",
        "",
    ]

    if random.random() < 0.14:
        return random.choice(invalid_formats)
    return random.choice(valid_formats)


def format_mixed_currency(amount: float) -> str:
    currency = random.choice(VALID_CURRENCIES)
    rendered = {
        "EUR": [f"EUR {amount:.2f}", f"€{amount:.2f}", f"{amount:.2f} EUR"],
        "USD": [f"USD {amount:.2f}", f"${amount:.2f}", f"{amount:.2f} USD"],
        "GBP": [f"GBP {amount:.2f}", f"£{amount:.2f}", f"{amount:.2f} GBP"],
    }
    if random.random() < 0.06:
        return ""
    return random.choice(rendered[currency])


def maybe_null(value: str, probability: float) -> str:
    return "" if random.random() < probability else value


def generate_email(customer_id: int) -> str:
    return f"customer{customer_id}@{random.choice(CUSTOMER_DOMAINS)}"


def generate_credit_card() -> str:
    prefix = random.choice(["4", "5"])
    return prefix + "".join(str(random.randint(0, 9)) for _ in range(15))


def build_record(index: int, base_date: datetime) -> dict[str, str]:
    customer_id = random.randint(10000, 99999)
    gross_amount = round(random.uniform(5, 5000), 2)
    quantity = random.randint(1, 12)
    unit_price = round(gross_amount / quantity, 2)
    transaction_date = random_date(base_date)

    record = {
        "transaction_id": f"LEG-{index:06d}",
        "order_date": format_mixed_date(transaction_date),
        "customer_id": str(customer_id),
        "customer_email": maybe_null(generate_email(customer_id), 0.08),
        "credit_card": maybe_null(generate_credit_card(), 0.12),
        "territory": maybe_null(random.choice(TERRITORIES), 0.05),
        "product_category": random.choice(PRODUCT_CATEGORIES),
        "sales_channel": random.choice(SALES_CHANNELS),
        "payment_method": random.choice(PAYMENT_METHODS),
        "quantity": maybe_null(str(quantity), 0.03),
        "unit_price": maybe_null(f"{unit_price:.2f}", 0.05),
        "gross_amount": format_mixed_currency(gross_amount),
        "legacy_status": random.choice(["ok", "pending", "unknown", "manual_review"]),
        "source_system": random.choice(["crm", "erp", "pos", "batch_import"]),
    }

    if random.random() < 0.04:
        record["quantity"] = "-1"
    if random.random() < 0.04:
        record["unit_price"] = "N/A"

    return record


def write_dataset(rows: int, output_path: Path) -> Path:
    random.seed(RANDOM_SEED)
    output_path.parent.mkdir(parents=True, exist_ok=True)

    fieldnames = [
        "transaction_id",
        "order_date",
        "customer_id",
        "customer_email",
        "credit_card",
        "territory",
        "product_category",
        "sales_channel",
        "payment_method",
        "quantity",
        "unit_price",
        "gross_amount",
        "legacy_status",
        "source_system",
    ]

    base_date = datetime(2022, 1, 1)
    with output_path.open("w", newline="", encoding="utf-8") as csv_file:
        writer = csv.DictWriter(csv_file, fieldnames=fieldnames)
        writer.writeheader()
        for index in range(1, rows + 1):
            writer.writerow(build_record(index, base_date))

    return output_path


def main() -> None:
    args = parse_args()
    output_path = write_dataset(rows=args.rows, output_path=args.output)
    print(f"Dataset legacy generado en: {output_path}")
    print(f"Filas generadas: {args.rows}")


if __name__ == "__main__":
    main()
