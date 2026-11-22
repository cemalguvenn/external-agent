import unittest

from cargo.binpack import pack_first_fit_decreasing, trucks_needed


class BinPackTests(unittest.TestCase):
    def test_single(self):
        self.assertEqual(trucks_needed([3], 10), 1)

    def test_two_small(self):
        self.assertEqual(trucks_needed([2, 3], 10), 1)

    def test_rejects_oversize(self):
        with self.assertRaises(ValueError):
            pack_first_fit_decreasing([11], 10)


if __name__ == "__main__":
    unittest.main()
