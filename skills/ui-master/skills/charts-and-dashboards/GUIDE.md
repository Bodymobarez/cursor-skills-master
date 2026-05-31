---
name: charts-and-dashboards
description: >-
  Build charts, data visualizations, and analytics dashboards. Use for any chart
  (line/bar/pie/area/scatter/heatmap/funnel/gauge), KPI cards, real-time dashboards,
  or BI-style reports. Covers chart-library selection, choosing the right chart,
  dashboard layout, performance with large data, theming, and accessibility.
---

# Charts & Dashboards

Build clear, fast, accessible charts and dashboards.

## 1. Choose the right chart for the question

| Goal | Chart |
|------|-------|
| Trend over time | **Line / area** |
| Compare categories | **Bar / column** |
| Part-to-whole | **Stacked bar** (prefer over pie); pie only for ≤3–4 slices |
| Correlation | **Scatter** |
| Distribution | **Histogram / box plot** |
| Conversion steps | **Funnel** |
| Density over 2 dims / time-of-day | **Heatmap** |
| Single metric vs target | **KPI card / gauge** |
| Geographic | **Map** (see `gis-maps` in backend-api-master) |

> Rule: pick the chart from the **question**, not the other way around.

## 2. Library by need

| Library | Strength |
|---------|----------|
| **Recharts** | React, declarative, fast to build standard charts |
| **ECharts** | Huge chart variety, performant, great for dashboards |
| **Chart.js** | Simple, canvas, lightweight |
| **visx / D3** | Fully custom / bespoke viz |
| **Nivo** | Beautiful defaults, React |
| **AG Charts / Highcharts** | Enterprise/financial features |
| **Tremor** | Prebuilt React dashboard components (KPI + charts + Tailwind) |

For a quick analytics dashboard in React+Tailwind: **Tremor** or **Recharts**. For heavy/varied
dashboards: **ECharts**.

## 3. Dashboard design principles

- **Inverted pyramid**: top = key KPIs (big numbers + delta vs prior period); below = trends;
  bottom = detail tables.
- **Grid layout** (responsive 12-col); consistent card sizing; group related metrics.
- **Context on every number**: comparison (vs last period), units, and a trend sparkline.
- **Filters** (date range, segment) apply to the whole board; persist in URL params.
- **Progressive disclosure**: summary first, drill-down on click.
- Limit to what answers a decision — avoid "everything" dashboards.

## 4. Performance with large data

```
- [ ] Aggregate server-side (don't ship 100k rows to draw 50 bars) — bucket in SQL
- [ ] Downsample time series (LTTB) for long ranges
- [ ] Canvas/WebGL renderer (ECharts/Chart.js) for >5k points
- [ ] Virtualize big tables; paginate
- [ ] Cache query results; debounce filter changes
- [ ] Lazy-load chart library + code-split dashboard routes
```

## 5. Theming & accessibility
- Drive colors from design tokens (pair with `brand-identity-creator`); support dark mode.
- **Color-blind-safe palettes**; never encode meaning by color alone — add labels/patterns.
- Provide a **data table fallback** + `aria-label`/`role="img"` with a text summary for screen readers.
- Readable axis labels, sensible number/date formatting, and units.

## Example (Recharts)

```jsx
<ResponsiveContainer width="100%" height={300}>
  <LineChart data={data} margin={{ top: 8, right: 16, bottom: 8, left: 0 }}>
    <CartesianGrid strokeDasharray="3 3" />
    <XAxis dataKey="date" /><YAxis />
    <Tooltip /><Legend />
    <Line type="monotone" dataKey="revenue" stroke="var(--color-primary)" dot={false} />
  </LineChart>
</ResponsiveContainer>
```

## Anti-patterns
- 3D charts, dual y-axes, and pie charts with many slices (mislead the reader).
- Truncated/non-zero bar baselines (exaggerate differences).
- Shipping raw rows to the client and aggregating in JS.
- Rainbow palettes; meaning encoded only by color; missing units/labels.
