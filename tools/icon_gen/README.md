# Centli icon generator

```bash
python tools/icon_gen/generate_app_icons.py
```

- Source: `logo/logo.png` (must not be modified by the script)
- Outputs: Android traditional + round mipmaps, adaptive foregrounds + XML, iOS AppIcon set
- Dependency: Pillow only
- Idempotent

Sampled adaptive background color is written to `android/.../values/ic_launcher_background.xml`.
