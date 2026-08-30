# ops adapter port

This port is the only product boundary between the console and the headless
factory. It consumes an immutable operation catalog, sends one typed intent only
after explicit acceptance, and reads typed result and view projections.

It imports released contracts only. It does not import runtime implementation
packages or repository working trees.
