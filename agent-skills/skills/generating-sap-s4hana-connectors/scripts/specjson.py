"""Read and write spec JSON the way the S/4HANA repos keep it.

Two details matter for byte-identical output:
  * number literals keep the spelling of the api.sap.com download (`1.0e-3`). A plain json
    round-trip writes `0.001`, and the bal sanitizers write `0.0010`; see respell().
  * 2-space indent, and no newline at the end of the file (the repos' specs have none).
"""
import json
from decimal import Decimal, InvalidOperation
from pathlib import Path


class Num(str):
    """A float literal kept as its original text."""


def load(path) -> object:
    return json.loads(Path(path).read_text(encoding="utf-8"), parse_float=Num)


def dumps(o, level: int = 0) -> str:
    pad, inner = "  " * level, "  " * (level + 1)
    if isinstance(o, Num):
        return str.__str__(o)
    if isinstance(o, dict):
        if not o:
            return "{}"
        items = [f"{inner}{json.dumps(k, ensure_ascii=False)}: {dumps(v, level + 1)}" for k, v in o.items()]
        return "{\n" + ",\n".join(items) + "\n" + pad + "}"
    if isinstance(o, list):
        if not o:
            return "[]"
        return "[\n" + ",\n".join(inner + dumps(v, level + 1) for v in o) + "\n" + pad + "]"
    return json.dumps(o, ensure_ascii=False)


def literals(o, found=None) -> dict:
    """Map each float literal's numeric value to its spelling, e.g. Decimal('0.001') -> '1.0e-3'."""
    found = {} if found is None else found
    if isinstance(o, Num):
        found.setdefault(Decimal(o), str.__str__(o))
    elif isinstance(o, dict):
        for v in o.values():
            literals(v, found)
    elif isinstance(o, list):
        for v in o:
            literals(v, found)
    return found


def respell(o, spelling: dict):
    """Give numbers the spelling they had before a bal script rewrote them (it writes 0.0010)."""
    if isinstance(o, Num):
        try:
            return Num(spelling.get(Decimal(o), o))
        except InvalidOperation:
            return o
    if isinstance(o, dict):
        return {k: respell(v, spelling) for k, v in o.items()}
    if isinstance(o, list):
        return [respell(v, spelling) for v in o]
    return o


def dump(o, path) -> None:
    Path(path).write_text(dumps(o), encoding="utf-8")
