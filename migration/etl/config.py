"""Utilidades de configuración y carga del manifiesto de migración."""

from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path

import yaml
from dotenv import load_dotenv

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_ENV_FILE = ROOT / ".env"
DEFAULT_MANIFEST = ROOT / "migration" / "config" / "migration.yaml"
DEFAULT_TESTS = ROOT / "migration" / "config" / "functional_tests.yaml"
DEFAULT_BENCHMARKS = ROOT / "migration" / "config" / "benchmark.yaml"


class ConfigError(RuntimeError):
    """Configuración ausente o inválida."""


def _load_env() -> None:
    if DEFAULT_ENV_FILE.exists():
        load_dotenv(DEFAULT_ENV_FILE, override=False)


def _env(name: str, default: str | None = None, *, required: bool = False) -> str:
    value = os.getenv(name, default)
    if required and (value is None or value == ""):
        raise ConfigError(
            f"Falta la variable {name}. Copia .env.example a .env y ajústala."
        )
    return value or ""


@dataclass(frozen=True)
class OracleSettings:
    dsn: str
    user: str
    password: str


@dataclass(frozen=True)
class EdbSettings:
    host: str
    port: int
    dbname: str
    user: str
    password: str
    sslmode: str = "prefer"


@dataclass(frozen=True)
class Settings:
    oracle: OracleSettings
    edb: EdbSettings
    batch_size: int
    report_dir: Path

    @classmethod
    def from_env(cls) -> "Settings":
        _load_env()
        dsn = _env("ORACLE_DSN", "localhost:1521/FREEPDB1")
        oracle = OracleSettings(
            dsn=dsn,
            user=_env("ORACLE_APP_USER", "ventas", required=True),
            password=_env("ORACLE_APP_PASSWORD", required=True),
        )
        edb = EdbSettings(
            host=_env("EDB_HOST", "localhost"),
            port=int(_env("EDB_PORT", "5444")),
            dbname=_env("EDB_DB", "ventas", required=True),
            user=_env("EDB_APP_USER", "ventas", required=True),
            password=_env("EDB_APP_PASSWORD", required=True),
            sslmode=_env("EDB_SSL_MODE", "prefer"),
        )
        report_dir = Path(_env("ETL_REPORT_DIR", "migration/reports"))
        if not report_dir.is_absolute():
            report_dir = ROOT / report_dir
        report_dir.mkdir(parents=True, exist_ok=True)
        return cls(
            oracle=oracle,
            edb=edb,
            batch_size=int(_env("ETL_BATCH_SIZE", "1000")),
            report_dir=report_dir,
        )


@dataclass(frozen=True)
class TableSpec:
    name: str
    columns: tuple[str, ...]
    select: str
    pk: tuple[str, ...]
    order: int

    def validate(self) -> None:
        if not self.name.isidentifier():
            raise ConfigError(f"Nombre de tabla inválido: {self.name!r}")
        if not self.columns:
            raise ConfigError(f"La tabla {self.name} no tiene columnas")
        missing = [c for c in self.pk if c not in self.columns]
        if missing:
            raise ConfigError(
                f"La PK de {self.name} usa columnas no incluidas: {missing}"
            )
        if self.select.rstrip().endswith(";"):
            raise ConfigError(
                f"El SELECT de {self.name} no debe terminar en ';' (psycopg/sqlplus)"
            )


@dataclass(frozen=True)
class SequenceSpec:
    name: str
    table: str
    column: str


@dataclass(frozen=True)
class IdentitySpec:
    table: str
    column: str


@dataclass(frozen=True)
class Manifest:
    oracle_schema: str
    edb_schema: str
    tables: tuple[TableSpec, ...]
    sequences: tuple[SequenceSpec, ...]
    identity_columns: tuple[IdentitySpec, ...]

    def table(self, name: str) -> TableSpec:
        for table in self.tables:
            if table.name == name:
                return table
        raise ConfigError(f"Tabla no encontrada en el manifiesto: {name}")

    @property
    def table_names(self) -> list[str]:
        return [t.name for t in self.tables]


def _read_yaml(path: Path) -> dict:
    if not path.exists():
        raise ConfigError(f"No existe el archivo de configuración: {path}")
    with path.open("r", encoding="utf-8") as handle:
        data = yaml.safe_load(handle) or {}
    if not isinstance(data, dict):
        raise ConfigError(f"El YAML debe ser un objeto: {path}")
    return data


def load_manifest(path: Path | None = None) -> Manifest:
    data = _read_yaml(path or DEFAULT_MANIFEST)
    raw_tables = data.get("tables") or []
    tables: list[TableSpec] = []
    for raw in raw_tables:
        table = TableSpec(
            name=str(raw["name"]),
            columns=tuple(str(c) for c in raw["columns"]),
            select=str(raw["select"]).strip(),
            pk=tuple(str(c) for c in raw.get("pk", [])),
            order=int(raw.get("order", 0)),
        )
        table.validate()
        tables.append(table)

    if not tables:
        raise ConfigError("El manifiesto no define tablas")
    if len({t.name for t in tables}) != len(tables):
        raise ConfigError("Hay tablas duplicadas en el manifiesto")
    if len({t.order for t in tables}) != len(tables):
        raise ConfigError("Hay valores 'order' duplicados en el manifiesto")

    sequences = tuple(
        SequenceSpec(
            name=str(s["name"]), table=str(s["table"]), column=str(s["column"])
        )
        for s in data.get("sequences", [])
    )
    identities = tuple(
        IdentitySpec(table=str(i["table"]), column=str(i["column"]))
        for i in data.get("identity_columns", [])
    )

    return Manifest(
        oracle_schema=str(data.get("oracle_schema", "VENTAS")),
        edb_schema=str(data.get("edb_schema", "ventas")),
        tables=tuple(sorted(tables, key=lambda t: t.order)),
        sequences=sequences,
        identity_columns=identities,
    )


def load_test_specs(path: Path | None = None) -> list[dict]:
    data = _read_yaml(path or DEFAULT_TESTS)
    tests = data.get("tests") or []
    if not isinstance(tests, list):
        raise ConfigError("functional_tests.yaml debe contener una lista 'tests'")
    return [dict(t) for t in tests]


def load_benchmark_specs(path: Path | None = None) -> list[dict]:
    data = _read_yaml(path or DEFAULT_BENCHMARKS)
    queries = data.get("queries") or []
    if not isinstance(queries, list):
        raise ConfigError("benchmark.yaml debe contener una lista 'queries'")
    return [dict(q) for q in queries]
