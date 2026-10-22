"""Regression coverage for the Cybertruck's authored scalar Bezier channels."""
import unittest
from convert_assets import parse_animation

class ChargingExportTest(unittest.TestCase):
    def test_bezier_retains_axis_path_values_and_handles(self):
        clip = parse_animation('''tracks/0/type = "bezier"
tracks/0/path = NodePath("Charge_Cap_Spatial:rotation_degrees:x")
tracks/0/interp = 1
tracks/0/keys = {
"points": PoolRealArray( -1.49586, -0.25, 0, 0.19821, 12.8201, 30.2938, -0.173996, -6.32466, 0.205472, 6.9248, 37.1704, -0.243672, -3.98314, 0.25, 0 ),
"times": PoolRealArray( 0, 0.5, 1 )
}''')
        track, = clip['tracks']
        self.assertEqual(track['target'], 'Charge_Cap_Spatial:rotation_degrees:x')
        self.assertEqual(track['times'], [0, .5, 1])
        self.assertEqual(track['values'], [-1.49586, 30.2938, 37.1704])
        self.assertEqual(track['handles'][1], [-.173996, -6.32466, .205472, 6.9248])

if __name__ == '__main__': unittest.main()
