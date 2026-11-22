# Plan: packing metrics

Both functions go in `cargo/packing.py`; tests go in `tests/test_packing.py`
(standard-library `unittest`, no new dependencies).

## Task 1 — utilization

`utilization(container: Box, items: list[Item]) -> float`

- Returns total item volume divided by container volume, rounded to 4 decimal places.
- Empty `items` returns `0.0`.
- Raises `ValueError` if the container volume is not positive.
- Raises `ValueError` if the items' total volume exceeds the container volume
  (an overfull container is a bug upstream, not a utilization of 1.2).

## Task 2 — fits

`fits(container: Box, item: Item) -> bool`

- True if the item fits inside the container in at least one of its six
  axis-aligned orientations (90° rotations only, no tilting).
- A dimension exactly equal to the container's counts as fitting.
- Raises `ValueError` if any item or container dimension is not positive.
