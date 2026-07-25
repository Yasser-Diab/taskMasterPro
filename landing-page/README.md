# TaskMaster Pro landing page

This is a dependency-free static website. Upload the contents of this directory
to any static host.

The page reads the latest published release from:

`https://github.com/Yasser-Diab/taskMasterPro/releases`

When a release contains `TaskMaster-Pro-Windows-<version>.exe` and
`TaskMaster-Pro-Android-<version>.apk`, the download buttons link directly to
those assets. Until then, both buttons fall back to the releases page.

To preview locally from the repository root:

```powershell
python -m http.server 4173 --directory landing-page
```

Then open `http://localhost:4173`.
