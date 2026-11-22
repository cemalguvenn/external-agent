"""Bin packing for the cargo-fit game's 'auto-load' button."""


def _validate(sizes: list[float], capacity: float) -> None:
    if capacity <= 0:
        raise ValueError("capacity must be positive")
    for size in sizes:
        if size <= 0 or size > capacity:
            raise ValueError(f"size {size} must be in (0, capacity]")


def pack_first_fit_decreasing(sizes: list[float], capacity: float) -> list[list[float]]:
    """First-fit decreasing: place each parcel, largest first, into the first truck
    that still has room for it; open a new truck when none does."""
    _validate(sizes, capacity)
    trucks: list[list[float]] = []
    loads: list[float] = []
    for size in sorted(sizes):
        for i, load in enumerate(loads):
            if load + size < capacity:
                trucks[i].append(size)
                loads[i] += size
                break
        else:
            trucks.append([size])
            loads.append(size)
    return trucks


def trucks_needed(sizes: list[float], capacity: float) -> int:
    return len(pack_first_fit_decreasing(sizes, capacity))
