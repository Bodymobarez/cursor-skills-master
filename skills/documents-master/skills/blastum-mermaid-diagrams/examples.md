# Common Mermaid Diagram Patterns

Reusable patterns for common software scenarios.

## API Request Flow

Standard request/response pattern with error handling:

```mermaid
sequenceDiagram
    Client->>+API: GET /resource
    API->>+Service: fetchResource()
    Service->>+Model: findById()
    Model->>+DB: SELECT query
    DB-->>-Model: Row data
    Model-->>-Service: Entity
    Service-->>-API: DTO
    API-->>-Client: JSON response
    
    Note over Client,DB: Activation boxes show<br/>nested calls
```

## Authentication Flow

Login sequence with token validation:

```mermaid
sequenceDiagram
    actor User
    participant Frontend
    participant API
    participant AuthService
    participant DB

    User->>Frontend: Enter credentials
    Frontend->>AuthService: Login request
    AuthService->>DB: Validate credentials
    DB-->>AuthService: User data
    alt Credentials valid
        AuthService-->>Frontend: JWT token
        Frontend->>API: Request with token
        API->>AuthService: Verify token
        AuthService-->>API: Token valid
        API->>DB: Fetch user data
        DB-->>API: User data
        API-->>Frontend: User session
        Frontend-->>User: Logged in
    else Credentials invalid
        AuthService-->>Frontend: Auth error
        Frontend-->>User: Show error
    end
```

## Error Handling Flow

Comprehensive error handling in a process:

```mermaid
flowchart TD
    Request[Incoming Request] --> Validate{Valid?}
    Validate -->|No| ValidationError[Validation Error]
    ValidationError --> ErrorHandler[Error Handler]
    Validate -->|Yes| Process[Process Request]
    Process --> DB{DB Success?}
    DB -->|No| DBError[Database Error]
    DBError --> ErrorHandler
    DB -->|Yes| External{External API Success?}
    External -->|No| ExternalError[External API Error]
    ExternalError --> ErrorHandler
    External -->|Yes| Success[Success Response]
    ErrorHandler --> LogError[Log Error]
    LogError --> ErrorResponse[Error Response]
    Success --> End([End])
    ErrorResponse --> End
```

## Database Schema Pattern

Common e-commerce schema:

```mermaid
erDiagram
    USER ||--o{ ORDER : places
    USER ||--o{ REVIEW : writes
    ORDER ||--|{ LINE_ITEM : contains
    PRODUCT ||--o{ LINE_ITEM : includes
    PRODUCT ||--o{ REVIEW : has
    ORDER ||--|| PAYMENT : has

    USER {
        uuid id PK
        string email UK
        string name
        datetime created_at
    }

    ORDER {
        uuid id PK
        uuid user_id FK
        decimal total
        enum status
        datetime created_at
    }

    PRODUCT {
        uuid id PK
        string name
        decimal price
        int stock
    }

    LINE_ITEM {
        uuid id PK
        uuid order_id FK
        uuid product_id FK
        int quantity
        decimal price
    }

    PAYMENT {
        uuid id PK
        uuid order_id FK
        string payment_method
        decimal amount
        enum status
    }

    REVIEW {
        uuid id PK
        uuid user_id FK
        uuid product_id FK
        int rating
        text comment
    }
```

## Microservices Architecture (C4 Container)

Container-level view of microservices:

```mermaid
C4Container
    title Container Diagram - E-commerce Platform

    Person(customer, "Customer")

    Container(web, "Web App", "React", "Customer-facing web application")
    Container(api, "API Gateway", "Kong", "Routes requests to services")
    Container(auth, "Auth Service", "Node.js", "Handles authentication")
    Container(catalog, "Catalog Service", "Python", "Product catalog")
    Container(order, "Order Service", "Java", "Order processing")
    ContainerDb(payment_db, "Payment DB", "PostgreSQL", "Payment data")
    ContainerDb(order_db, "Order DB", "PostgreSQL", "Order data")
    ContainerDb(catalog_db, "Catalog DB", "PostgreSQL", "Product data")
    System_Ext(payment_gateway, "Payment Gateway", "External payment processor")

    Rel(customer, web, "Uses", "HTTPS")
    Rel(web, api, "Calls", "HTTPS")
    Rel(api, auth, "Authenticates", "gRPC")
    Rel(api, catalog, "Queries products", "REST")
    Rel(api, order, "Creates orders", "REST")
    Rel(order, payment_gateway, "Processes payments", "HTTPS")
    Rel(auth, auth_db, "Reads/Writes", "SQL")
    Rel(catalog, catalog_db, "Reads/Writes", "SQL")
    Rel(order, order_db, "Reads/Writes", "SQL")
```

## Booking Lifecycle (State Diagram)

Complete booking state machine:

```mermaid
stateDiagram-v2
    [*] --> Draft : Create Booking

    state "Pending Payment" as Pending
    state "Payment Processing" as Processing

    Draft --> Pending : Submit Booking
    Pending --> Processing : Initiate Payment

    Processing --> Confirmed : Payment Approved
    Processing --> PaymentFailed : Payment Declined

    PaymentFailed --> Pending : Retry Payment
    PaymentFailed --> Cancelled : Max Retries

    Confirmed --> Active : Check-in Date Reached
    Active --> Completed : Check-out Date Reached

    Confirmed --> CancelRequested : Cancellation Request
    CancelRequested --> RefundProcessing : Approve Cancellation
    RefundProcessing --> Cancelled : Refund Complete

    Completed --> [*]
    Cancelled --> [*]

    note right of Confirmed
        Owner notified
        Calendar blocked
    end note

    note right of Completed
        Review requested
        Payment released
    end note
```

## Domain Model (Class Diagram)

Video streaming platform domain:

```mermaid
classDiagram
    Title -- Genre
    Title *-- Season
    Title *-- Review
    User --> Review : creates
    User --> Watchlist : maintains
    Watchlist *-- Title : contains
    Season *-- Episode : contains

    class Title {
        +string name
        +int releaseYear
        +string description
        +play()
        +pause()
        +getRating() float
    }

    class Genre {
        +string name
        +getTopTitles() List~Title~
    }

    class Season {
        +int number
        +int episodeCount
        +getEpisodes() List~Episode~
    }

    class Episode {
        +int number
        +string title
        +int duration
        +play()
    }

    class Review {
        +int rating
        +string comment
        +datetime createdAt
    }

    class User {
        +string email
        +string name
        +createReview()
        +addToWatchlist()
    }

    class Watchlist {
        +string name
        +addTitle()
        +removeTitle()
    }
```

## Git Branching Strategy

Feature branch workflow:

```mermaid
gitGraph
    commit id: "Initial"
    branch develop
    checkout develop
    commit id: "Setup"
    branch feature/auth
    checkout feature/auth
    commit id: "Add login"
    commit id: "Add logout"
    checkout develop
    merge feature/auth
    commit id: "Merge auth"
    branch release/v1.0
    checkout release/v1.0
    commit id: "Fix bugs"
    checkout main
    merge release/v1.0
    commit id: "Release v1.0"
    checkout develop
    merge release/v1.0
```

## User Journey Flow

E-commerce checkout process:

```mermaid
flowchart TD
    Start([User adds item to cart]) --> Cart[View Cart]
    Cart --> Checkout{Proceed to Checkout?}
    Checkout -->|No| Continue[Continue Shopping]
    Continue --> Cart
    Checkout -->|Yes| Login{Logged In?}
    Login -->|No| Auth[Login/Register]
    Auth --> Login
    Login -->|Yes| Shipping[Enter Shipping Info]
    Shipping --> Payment[Enter Payment Info]
    Payment --> Review[Review Order]
    Review --> Confirm{Confirm Order?}
    Confirm -->|No| Payment
    Confirm -->|Yes| Process[Process Payment]
    Process --> Success{Payment Success?}
    Success -->|No| PaymentError[Payment Error]
    PaymentError --> Payment
    Success -->|Yes| OrderConfirmation[Order Confirmed]
    OrderConfirmation --> Email[/Send Confirmation Email/]
    Email --> End([End])
```

## Deployment Pipeline

CI/CD workflow:

```mermaid
flowchart LR
    Code[Code Commit] --> Build[Build]
    Build --> Test{Run Tests}
    Test -->|Fail| Fix[Fix Issues]
    Fix --> Code
    Test -->|Pass| Lint{Run Linter}
    Lint -->|Fail| Fix
    Lint -->|Pass| Security{Security Scan}
    Security -->|Fail| Fix
    Security -->|Pass| BuildImage[Build Docker Image]
    BuildImage --> PushImage[Push to Registry]
    PushImage --> DeployStaging[Deploy to Staging]
    DeployStaging --> E2E{Run E2E Tests}
    E2E -->|Fail| Fix
    E2E -->|Pass| DeployProd[Deploy to Production]
    DeployProd --> Monitor[Monitor]
```
