"""Packing helpers for the cargo-fit game."""
from .models import Box, Item


def total_volume(items: list[Item]) -> float:
    """Sum of item volumes."""
    return sum(item.volume for item in items)
