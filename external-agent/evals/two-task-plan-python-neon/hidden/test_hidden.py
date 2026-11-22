"""Hidden acceptance tests: run from the repo root with
python3 -m unittest <path>/test_hidden.py  (repo root on sys.path)."""
import unittest

from cargo.models import Box, Item
from cargo.packing import fits, utilization


class HiddenUtilization(unittest.TestCase):
    def test_basic(self):
        self.assertEqual(utilization(Box(10, 10, 10), [Item("a", 5, 10, 10)]), 0.5)

    def test_rounding(self):
        self.assertEqual(utilization(Box(3, 1, 1), [Item("a", 1, 1, 1)]), 0.3333)

    def test_empty(self):
        self.assertEqual(utilization(Box(1, 2, 3), []), 0.0)

    def test_full(self):
        self.assertEqual(utilization(Box(2, 2, 2), [Item("a", 2, 2, 2)]), 1.0)

    def test_zero_container(self):
        with self.assertRaises(ValueError):
            utilization(Box(0, 10, 10), [])

    def test_negative_container(self):
        with self.assertRaises(ValueError):
            utilization(Box(-1, 10, 10), [])

    def test_overfull(self):
        with self.assertRaises(ValueError):
            utilization(Box(1, 1, 1), [Item("a", 1, 1, 1), Item("b", 1, 1, 1)])


class HiddenFits(unittest.TestCase):
    def test_rotation_needed(self):
        self.assertTrue(fits(Box(10, 20, 30), Item("a", 30, 10, 20)))

    def test_every_permutation(self):
        import itertools
        for dims in itertools.permutations((5, 7, 9)):
            self.assertTrue(fits(Box(9, 5, 7), Item("a", *dims)), dims)

    def test_exact(self):
        self.assertTrue(fits(Box(4, 5, 6), Item("a", 4, 5, 6)))

    def test_too_big(self):
        self.assertFalse(fits(Box(10, 20, 30), Item("a", 31, 1, 1)))

    def test_no_orientation_works(self):
        # Each dim fits some axis but no single orientation fits all three.
        self.assertFalse(fits(Box(10, 10, 30), Item("a", 25, 25, 5)))

    def test_zero_item_dim(self):
        with self.assertRaises(ValueError):
            fits(Box(10, 10, 10), Item("a", 0, 1, 1))

    def test_negative_container_dim(self):
        with self.assertRaises(ValueError):
            fits(Box(10, -10, 10), Item("a", 1, 1, 1))


if __name__ == "__main__":
    unittest.main()
