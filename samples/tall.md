# Tall diagram scrolling

Place the cursor on the Mermaid fence and press Enter once. Use normal Vim
motions, `/` to search, or visual selection and `y` to copy rendered text.
Press `q` or `Esc` in Normal mode to return to the Markdown source.

```mermaid
flowchart TD
    A[Start] --> B[Read configuration]
    B --> C[Validate inputs]
    C --> D[Load dependencies]
    D --> E[Collect data]
    E --> F[Transform records]
    F --> G[Check results]
    G --> H[Write output]
    H --> I[Publish artifacts]
    I --> J[Send notification]
    J --> K[Clean up]
    K --> L[Finish]
```

This paragraph stays part of the Markdown document. Scrolling the diagram does
not move the source cursor or modify this file.
