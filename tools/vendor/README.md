`open-simplex-noise.c` and `.h` are the public-domain OpenSimplex implementation by Kurt Spencer / Stephen M. Cameron, with Godot's allocation-free context changes. Retrieved from [Godot 3.5](https://github.com/godotengine/godot/tree/3.5/thirdparty/misc).

`source_noise.py` reproduces the seamless 4D sampling used by [Godot's OpenSimplexNoise](https://github.com/godotengine/godot/blob/3.5/modules/opensimplex/open_simplex_noise.cpp), using the APK's `noiseTexture.tres` settings. This is an engine algorithm, not an invented texture or a replacement asset.
