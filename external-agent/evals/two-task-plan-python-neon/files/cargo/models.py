from dataclasses import dataclass


@dataclass(frozen=True)
class Box:
    """A cargo container. Dimensions in centimetres."""
    length: float
    width: float
    height: float

    @property
    def volume(self) -> float:
        return self.length * self.width * self.height


@dataclass(frozen=True)
class Item:
    """A parcel to load. Dimensions in centimetres, weight in kg."""
    name: str
    length: float
    width: float
    height: float
    weight: float = 0.0

    @property
    def volume(self) -> float:
        return self.length * self.width * self.height
