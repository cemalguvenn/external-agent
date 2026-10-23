import unittest

from cargo.models import Box, Item
from cargo.packing import total_volume


class ModelTests(unittest.TestCase):
    def test_box_volume(self):
        self.assertEqual(Box(10, 20, 30).volume, 6000)

    def test_total_volume(self):
        items = [Item("a", 1, 2, 3), Item("b", 2, 2, 2)]
        self.assertEqual(total_volume(items), 14)


if __name__ == "__main__":
    unittest.main()
