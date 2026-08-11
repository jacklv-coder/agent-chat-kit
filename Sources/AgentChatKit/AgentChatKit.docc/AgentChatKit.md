# ``AgentChatKit``

Build native iPhone and iPad agent conversations while keeping model, tool, transport, and
authorization decisions in the host application.

## Overview

AgentChatKit accepts structured ``AgentRuntimeEvent`` values from an
``AgentRuntimeAdapter``, reduces them into a deterministic ``AgentConversationSnapshot``, and
renders the result with native UIKit. It never performs model requests, shell commands, file
operations, navigation, or approvals on behalf of the host.

Start with <doc:GettingStarted>, review <doc:ConversationExperience> for the complete page and
scrolling contract, then use <doc:RuntimeAdapter> to connect a real runtime. Use
<doc:TestingScenarios> to replay the same deterministic fixture in the Demo and automated tests.

## Topics

### Essentials

- <doc:GettingStarted>
- <doc:ConversationExperience>
- <doc:RuntimeAdapter>
- <doc:ComposerIntegration>
- <doc:TestingScenarios>

### Runtime

- ``AgentRuntimeAdapter``
- ``AgentRuntimeConnection``
- ``AgentRuntimeEvent``
- ``AgentRuntimeCommand``
- ``AgentChatSession``

### Presentation

- ``AgentConversationViewController``
- ``AgentConversationConfiguration``
- ``AgentComposerState``
- ``AgentComposerAccessory``
