# Charts (Pie and Bar)

Mermaid supports pie charts and bar charts for data visualization.

## Pie Charts

### Basic Syntax
```mermaid
pie title Distribution of Sales
    "Product A" : 45
    "Product B" : 30
    "Product C" : 25
```

### Example: Market Share
```mermaid
pie title Market Share by Company
    "Company A" : 35
    "Company B" : 28
    "Company C" : 20
    "Company D" : 12
    "Others" : 5
```

### Example: Budget Allocation
```mermaid
pie title Annual Budget Allocation
    "Development" : 40
    "Marketing" : 25
    "Operations" : 20
    "Support" : 10
    "Other" : 5
```

### Example: User Demographics
```mermaid
pie title User Age Distribution
    "18-25" : 30
    "26-35" : 35
    "36-45" : 20
    "46-55" : 10
    "56+" : 5
```

## Bar Charts

### Basic Syntax
```mermaid
xychart-beta
    title "Sales Revenue"
    x-axis [Jan, Feb, Mar, Apr, May, Jun, Jul, Aug, Sep, Oct, Nov, Dec]
    y-axis "Revenue (in $)" 0 --> 100000
    bar [5000, 6000, 7500, 8200, 9500, 10500, 11000, 10200, 9200, 8500, 7000, 6000]
```

### Example: Monthly Sales
```mermaid
xychart-beta
    title "Monthly Sales Performance"
    x-axis [Jan, Feb, Mar, Apr, May, Jun]
    y-axis "Sales ($)" 0 --> 50000
    bar [12000, 19000, 30000, 50000, 40000, 35000]
```

### Example: Comparison Chart
```mermaid
xychart-beta
    title "Product Sales Comparison"
    x-axis [Q1, Q2, Q3, Q4]
    y-axis "Units Sold" 0 --> 1000
    bar [200, 300, 400, 500]
    bar [150, 250, 350, 450]
```

### Example: Multiple Series
```mermaid
xychart-beta
    title "Revenue by Product Category"
    x-axis [2021, 2022, 2023, 2024]
    y-axis "Revenue ($)" 0 --> 200000
    bar [50000, 75000, 100000, 150000]
    bar [30000, 45000, 60000, 90000]
    bar [20000, 30000, 40000, 60000]
```

## Best Practices

1. **Clear titles** - Describe what the chart shows
2. **Appropriate scale** - Set y-axis range appropriately
3. **Meaningful labels** - Use descriptive category names
4. **Consistent units** - Use same units throughout
5. **Limit categories** - Too many slices/bars reduce readability
6. **Order data** - Sort by value for easier comparison

## Common Use Cases

- **Market Analysis** - Market share, competitor analysis
- **Budget Planning** - Budget allocation, spending breakdown
- **Performance Metrics** - Sales trends, user growth
- **Survey Results** - Response distribution, demographics
- **Resource Allocation** - Team distribution, time allocation

## Limitations

- Pie charts: Limited to showing proportions/percentages
- Bar charts: Basic visualization, limited customization
- For complex visualizations, consider exporting to specialized tools
