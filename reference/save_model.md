# Save and load a Meridian model

`save_model()` serializes a Meridian model – including its inference
data – to a file, and `load_model()` restores it.

## Usage

``` r
save_model(model, path)

load_model(path)
```

## Arguments

- model:

  A `meridian_model`.

- path:

  File path to write to or read from.

## Value

`save_model()` returns the path actually written, invisibly (it can
differ from `path` when an extension was added); `load_model()` returns
a `meridian_model`.

## Details

Meridian has two file formats, and the file extension selects which one
is used:

- **Schema** (`.binpb` binary, or `.txtpb` / `.textproto` text):
  Meridian's versioned protobuf format, via
  `meridian.schema.serde.meridian_serde`. It can be read by other
  Meridian versions and is the format Meridian recommends from 2.2 on.
  It needs the `google-meridian[schema]` extra, which
  [`install_meridian()`](https://roeh-marketing.github.io/meridianR/reference/install_meridian.md)
  installs.

- **Pickle** (`.pkl`, `.pickle`, `.joblib`): Meridian's legacy
  `save_mmm()` / `load_mmm()`. Only guaranteed to reload with the same
  Meridian version, and deprecated in Meridian 2.2.

Any other extension (or none) uses the schema format when it is
available – `.binpb` is appended to the file name – and falls back to
pickle otherwise.

## Examples

``` r
if (FALSE) { # \dontrun{
save_model(mmm, "mmm.binpb")   # schema format (recommended)
mmm2 <- load_model("mmm.binpb")

save_model(mmm, "mmm.pkl")     # legacy pickle format
} # }
```
