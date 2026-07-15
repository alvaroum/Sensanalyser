# Spider / Radar Plots — how to configure them

Spider (radar) plots are generated in Phase 8 by
`run_figure_phase()` → `create_spider_plot_data()` → `plot_spider_profiles()`
in `R/functions/figure_helpers.R`. You never edit R code to change them — everything
is driven by the `outputs.spider` (and `outputs.figure`) blocks of your project
`settings.yaml`.

For each chart the engine:

1. picks the **grouping factor** (the first factor, normally `product`),
2. computes the mean of each attribute per group,
3. draws one radar polygon per group.

---

## The two blocks you edit

```yaml
outputs:
  figures:
    spider: true              # master on/off switch for spider plots

  figure:
    palette: Set1             # RColorBrewer palette used for the polygons
    width: 9                  # inches
    height: 6
    dpi: 300

  spider:
    top_n_attributes: ~       # ~ = all; N = keep only the N highest-mean attributes
    significant_only: false   # true = only omnibus-significant attributes (needs post-hoc)
    attributes: ~             # ~ = all analysed attributes; or an explicit list
    label_size: ~             # ~ = auto; a number (cex) to force axis-label size
    legend: auto              # auto = hide for single-product charts; true / false to force
    colors: {}                # fixed colour per product (see "Fixing colours" below)
    scale_min: 0              # radial axis minimum
    scale_max: ~              # ~ = auto-fit each chart; or a fixed number (see "Scale")
    axis_labels: value        # value = real scale values / percent = 0-100% / none
    axis_unit: ""             # suffix on tick labels, e.g. "%" or " cm"
    axis_steps: 4             # number of rings
    comparisons: {}           # <-- THIS is where you define the plots you want
```

### How the attribute pool is decided (applied in this order)

1. Start from all analysed attributes (`variables.attributes`).
2. If `significant_only: true`, keep only attributes whose omnibus test is
   significant. This requires `model.posthoc.run: true` so letters exist.
3. If `attributes:` is a list, intersect with it.
4. If `top_n_attributes: N`, keep the N attributes with the highest global mean.

`top_n` is ranked across the **full** dataset before any product filtering, so the
same axes appear on every comparison chart.

---

## Defining the plots you want — `comparisons`

`comparisons` is a **named map**. Each key produces one file:

```
outputs/figures/spiderplots/spider_<key>.png
outputs/tables/spiderplots/spider_<key>_means.csv
```

The value is either:

- `~` (null) → put **every product** on that chart, or
- a **list of product display names** to include on that chart.

```yaml
outputs:
  spider:
    comparisons:
      all_products: ~                       # one chart with everything
      naked_organic_range:                  # one chart, three products
        - Naked organic - Great seeds
        - Naked organic - twenty four grains and seeds
        - Naked organic- wheat
      control_vs_daves:                     # one chart, two products
        - Control commercial sample
        - Dave's killer bread - organic- 100 % whole wheat
```

This writes `spider_all_products.png`, `spider_naked_organic_range.png`, and
`spider_control_vs_daves.png`. The key is also used (underscores → spaces) as the
chart title.

### Setting a custom chart title

By default the title is the comparison key with underscores turned into spaces
(`naked_organic_range` → "naked organic range"). To set an exact title — with
capitalisation, punctuation or spaces the key can't hold — give the comparison a
mapping with `title:` and `products:` instead of a bare list:

```yaml
outputs:
  spider:
    comparisons:
      dave_whole:
        title: "Dave's Killer Bread — 100% Whole Wheat"
        products:
          - Dave's killer bread - organic- 100 % whole wheat
      house_vs_control:
        title: "House recipe vs. commercial control"
        products:
          - Control commercial sample
          - Dave's killer bread - organic- white bread done right
```

The filename still comes from the key (`spider_dave_whole.png`); only the on-chart
title changes. `products:` follows the same rules as a bare list (use `~` or omit
it for all products). You can freely mix both forms across comparisons.

### Readability — labels and legend overlap

Long attribute names and the legend used to collide at the bottom of the radar.
The engine now:

- **auto-wraps** long axis labels onto two lines and **shrinks** them as the
  number of axes grows (override with `label_size:`, e.g. `0.7`);
- **hides the legend on single-product charts** — the title already names the
  product — so nothing overlaps the bottom axis label. Set `legend: true` to force
  it back, or `legend: false` to always suppress it;
- places multi-product legends **below** the plot, stacking into columns when
  there are many groups.

If labels still feel cramped on a busy chart, widen the canvas via
`outputs.figure.width` / `height`, or drop `label_size` a notch.

If `comparisons` is empty (`{}` or `[]`), the engine falls back to a single
`all_products` chart with every product.

### ⚠️ Two things that trip people up

1. **Use display names, not raw codes.** Names are matched *after* aliases in
   `labels.aliases.product` are applied. In this project
   `Commercial white bread` is aliased to `Control commercial sample`, so you must
   write `Control commercial sample` in `comparisons`. A name that matches nothing
   aborts that one chart with a warning (the others still render).

2. **`comparisons` must be a mapping once it has entries.** An empty `[]` is
   accepted, but as soon as you add a plot it has to be `key:` followed by an
   indented value — not a YAML list.

---

## Recipes

**One clean chart per product family**

```yaml
outputs:
  spider:
    comparisons:
      sauerteig_breads:
        - Alnavit Sauerteig-brot
        - Schnitzer sauerteig- brot
      rye_breads:
        - Biona organic - Organic rye bread original
        - Finntoast- Organic rye bread
        - Terrasana - rye bread linseed
```

**Only the discriminating attributes, all products**

```yaml
outputs:
  spider:
    significant_only: true      # needs model.posthoc.run: true
    comparisons:
      significant_profile: ~
```

**Top 8 attributes, a focused subset of attributes**

```yaml
outputs:
  spider:
    top_n_attributes: 8
    attributes:
      - firmness_m
      - moistness_m
      - cohesiveness_m
      - chewiness_m
      - density_t
      - crumbliness_t
      - resistance_t
      - smoothness_t
    comparisons:
      texture_topN: ~
```

---

## Fixing colours (stable per product, or per plot)

By default each chart colours its polygons in group order from
`outputs.figure.palette`, so the *same product can get a different colour on
different charts* (Control might be red on one plot and blue on another). Two
settings fix that.

**Global — pin a colour to each product (applies to every chart):**

```yaml
outputs:
  spider:
    colors:
      Control commercial sample: "#7F7F7F"          # always grey
      Dave's killer bread - organic- 100 % whole wheat: "#2CA02C"   # always green
    comparisons:
      dave_whole_vs_control: [Dave's killer bread - organic- 100 % whole wheat, Control commercial sample]
      dave_white_vs_control: [Dave's killer bread - organic- white bread done right, Control commercial sample]
```

Keys are **product display names** (post-alias, same as in `comparisons`). Values
are any R colour — a hex code (`"#2CA02C"`) or a name (`"firebrick"`). Products
you don't list keep falling back to the palette. Because the mapping is by name,
a pinned product keeps its colour no matter which chart it appears on or in what
order.

**Per-plot — override colours for one chart only** (uses the mapping form of a
comparison):

```yaml
outputs:
  spider:
    comparisons:
      house_vs_control:
        title: "House recipe vs. control"
        products: [House recipe, Control commercial sample]
        colors:                         # named -> merges over the global map
          House recipe: "#FF7F00"
        # colors: ["#6A3D9A", "#FF7F00"] # OR positional, in product order
```

A **named** per-plot `colors` map merges on top of the global `colors` for that
chart; an **unnamed list** is applied positionally (in the chart's product order)
and replaces the global colours for that chart only.

---

## Scale — max value and axis units

By default each chart **auto-fits** its own outer ring to ~110% of the largest
mean, and (an fmsb quirk) labels the rings as **percent of that range**
(`0 (%)`, `25 (%)`, …) rather than the real sensory scale. Four settings fix
this.

```yaml
outputs:
  spider:
    scale_min: 0          # inner value (usually 0)
    scale_max: 15          # outer ring value — fix it to your panel scale
    axis_labels: value     # show real values (0, 3, 6, 9, 12, 15)
    axis_unit: ""          # append to each label, e.g. "%" -> "3%"
    axis_steps: 5          # number of rings between min and max
```

- **`scale_max`** sets the outer ring. Use a fixed number (e.g. your panel's
  0–15 line scale) so every chart is directly comparable; leave it `~` to let
  each chart auto-fit. `scale_min` is the centre value (normally `0`).
- **`axis_labels`** chooses what the rings say:
  - `value` (default) — the actual scale values from `scale_min` to `scale_max`;
  - `percent` — fmsb's old `0–100%` of the range;
  - `none` — no ring labels.
- **`axis_unit`** is appended to each value label (`"%"`, `" cm"`, `" g"`, …).
- **`axis_steps`** is how many rings to draw (label count is `axis_steps + 1`).
  With `scale_max: 15, axis_steps: 5` you get rings at 0, 3, 6, 9, 12, 15.

**Per-plot scale.** A single chart can override the scale via the mapping form —
handy for a zoomed-in comparison while the rest stay on the shared scale:

```yaml
comparisons:
  fine_detail:
    title: "Aroma detail (zoomed)"
    products: [Trial A, Trial B]
    scale_max: 6            # this chart only
```

For cross-chart comparability, prefer a single global `scale_max` and leave the
per-plot override for the exceptions.

---

## Notes on rendering

- Colours default to `outputs.figure.palette` (any RColorBrewer name) in group
  order; pin them with `outputs.spider.colors` (above). With more groups than the
  palette has, colours are interpolated.
- Radar charts need **at least 3 axes**. If a chart ends up with 1–2 attributes
  (e.g. a derived-attribute subset), the engine automatically saves a faceted bar
  chart instead of failing.
- The axis maximum auto-scales to ~110% of the largest mean unless you set
  `scale_max` (see "Scale" above); tick labels default to real scale values.
