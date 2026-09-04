# DevNotch Homebrew Tap Bootstrap

Create an empty public repository named `homebrew-devnotch` under the same GitHub owner as the application repository. Its default branch must be `main` and it must contain:

```text
homebrew-devnotch/
└── Casks/
    └── devnotch.rb
```

Render the initial Cask only after a notarized release exists:

```sh
scripts/render-homebrew-cask \
  0.1.0 \
  <release-sha256> \
  DevNNNotch/DevNotch \
  /path/to/homebrew-devnotch/Casks/devnotch.rb
```

The application release workflow updates this file for each stable tag. See `docs/RELEASING.md` for the required repository token.
