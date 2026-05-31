# State Diagrams

State diagrams model state machines and lifecycles. They show how entities transition between states based on events or conditions.

## Basic Syntax

```mermaid
stateDiagram-v2
    [*] --> State1
    State1 --> State2 : Event
    State2 --> [*]
```

## States

### Simple States
```mermaid
stateDiagram-v2
    [*] --> Idle
    Idle --> Active : Start
    Active --> [*] : Stop
```

### Named States with Aliases
```mermaid
stateDiagram-v2
    [*] --> Draft
    
    state "Pending Payment" as Pending
    state "Payment Processing" as Processing
    
    Draft --> Pending : Submit
    Pending --> Processing : Initiate Payment
    Processing --> Confirmed : Payment Approved
    Processing --> Failed : Payment Declined
```

## Transitions

### Basic Transition
```mermaid
stateDiagram-v2
    State1 --> State2 : Event
```

### Transition with Condition
```mermaid
stateDiagram-v2
    Pending --> Confirmed : Payment Success
    Pending --> Cancelled : Payment Failed
    Pending --> Cancelled : User Cancels
```

### Self-Transition
```mermaid
stateDiagram-v2
    Processing --> Processing : Retry
```

## Composite States

States can contain nested states:

```mermaid
stateDiagram-v2
    [*] --> Active
    
    state Active {
        [*] --> Idle
        Idle --> Running : Start
        Running --> Idle : Stop
        Running --> Error : Failure
        Error --> Idle : Reset
    }
    
    Active --> [*] : Shutdown
```

## Concurrent States

Show parallel state machines:

```mermaid
stateDiagram-v2
    [*] --> Active
    
    state Active {
        [*] --> UI
        [*] --> Backend
        
        state UI {
            [*] --> Loading
            Loading --> Ready
            Ready --> Error
        }
        
        state Backend {
            [*] --> Initializing
            Initializing --> Running
            Running --> Stopped
        }
    }
    
    Active --> [*] : Shutdown
```

## Notes

Add explanatory notes to states:

```mermaid
stateDiagram-v2
    [*] --> Draft
    Draft --> Pending : Submit
    Pending --> Confirmed : Payment Success
    
    note right of Confirmed
        Owner notified
        Calendar blocked
        Email sent
    end note
    
    note left of Pending
        Waiting for payment
        Can be cancelled
    end note
```

## History States

Remember previous state:

```mermaid
stateDiagram-v2
    [*] --> Active
    
    state Active {
        [*] --> State1
        State1 --> State2
        State2 --> State3
        
        [*] --> HistoryState
        HistoryState --> State1 : Resume
    }
    
    Active --> Paused : Pause
    Paused --> Active : Resume
```

## Choice Points

Add decision logic:

```mermaid
stateDiagram-v2
    [*] --> Processing
    Processing --> Choice1{Valid?}
    Choice1 -->|Yes| Success
    Choice1 -->|No| Error
    Success --> [*]
    Error --> [*]
```

## Fork and Join

Parallel execution:

```mermaid
stateDiagram-v2
    [*] --> Fork
    Fork --> State1
    Fork --> State2
    Fork --> State3
    State1 --> Join
    State2 --> Join
    State3 --> Join
    Join --> [*]
```

## Comprehensive Example: Order Lifecycle

```mermaid
stateDiagram-v2
    [*] --> Draft : Create Order
    
    state "Pending Payment" as Pending
    state "Payment Processing" as Processing
    
    Draft --> Pending : Submit Order
    Pending --> Processing : Initiate Payment
    
    Processing --> Confirmed : Payment Approved
    Processing --> PaymentFailed : Payment Declined
    
    PaymentFailed --> Pending : Retry Payment
    PaymentFailed --> Cancelled : Max Retries Reached
    
    Confirmed --> Shipped : Ship Order
    Confirmed --> CancelRequested : Customer Cancels
    
    CancelRequested --> RefundProcessing : Approve Cancellation
    RefundProcessing --> Cancelled : Refund Complete
    
    Shipped --> Delivered : Delivery Confirmed
    Delivered --> Completed : Customer Confirms
    
    Cancelled --> [*]
    Completed --> [*]
    
    note right of Confirmed
        Inventory reserved
        Payment captured
        Email sent
    end note
    
    note right of Shipped
        Tracking number generated
        Customer notified
    end note
```

## User Account States

```mermaid
stateDiagram-v2
    [*] --> Unverified : Sign Up
    
    state Account {
        Unverified --> Verified : Email Verified
        Verified --> Active : First Login
        Active --> Suspended : Violation
        Suspended --> Active : Appeal Approved
        Suspended --> Banned : Appeal Denied
        Active --> Inactive : 90 Days Inactive
        Inactive --> Active : Login
        Banned --> [*] : Permanent
    }
    
    Account --> [*] : Delete Account
```

## Workflow Approval States

```mermaid
stateDiagram-v2
    [*] --> Draft : Create Request
    
    Draft --> Submitted : Submit
    Submitted --> Reviewing : Assign Reviewer
    
    Reviewing --> Approved : Approve
    Reviewing --> Rejected : Reject
    Reviewing --> NeedsRevision : Request Changes
    
    NeedsRevision --> Draft : Revise
    NeedsRevision --> Submitted : Resubmit
    
    Approved --> Implemented : Complete
    Rejected --> [*]
    Implemented --> [*]
    
    note right of Reviewing
        Can be escalated
        Multiple reviewers possible
    end note
```

## Best Practices

1. **Clear state names** - Use descriptive, action-oriented names
2. **Show all transitions** - Include error paths and edge cases
3. **Mark terminal states** - Use `[*]` for start and end
4. **Add notes** - Explain complex states or important behaviors
5. **Group related states** - Use composite states for organization
6. **Show conditions** - Label transitions with triggering events
7. **Avoid deep nesting** - Keep state hierarchies manageable

## Common Use Cases

- **Order/Booking Lifecycles** - Track status through workflow
- **User Account States** - Authentication and account status
- **Document Workflows** - Approval and review processes
- **System States** - Application lifecycle (starting, running, stopping)
- **Process States** - Multi-step processes with checkpoints
- **Entity Lifecycles** - Creation, modification, deletion states
