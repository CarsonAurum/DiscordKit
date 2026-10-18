# ``DiscordInteractions``

Authenticate signed HTTP ingress and own one bounded interaction response lifecycle.

## Overview

DiscordInteractions supports independently adopted HTTP interaction applications, Gateway-delivered response ownership and durable webhook-event admission. It does not start a listener, choose a delivery mode or register commands. The host injects exact request bytes, clocks, response sinks and cleanup.

Start with <doc:AuthenticatingIngress>, then read <doc:RespondingToInteractions> for acknowledgement/defer ownership. <doc:WebhookEventsAndPreviews> distinguishes durable event delivery and display-only previews.

## Topics

### Signed applications

- <doc:AuthenticatingIngress>
- <doc:RespondingToInteractions>
- <doc:WebhookEventsAndPreviews>

### API reference

- <doc:APIReference>
