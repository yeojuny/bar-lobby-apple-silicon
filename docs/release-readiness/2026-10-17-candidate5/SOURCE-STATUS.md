# Candidate.5 corresponding source status

Download sources.tar.gz, notices.tar.gz and SHA256SUMS from the exact release. Eleven preferred component archives include the current launcher, both populated native engine trees, exact overlay/profile inputs and unchanged shared graphics/dependency sources. GitHub's automatic launcher-only archive is not the complete application source.

The manifest and build-notes/candidate-source-correspondence.json bind the source archives to the frozen app inventory, ASAR and both native engine hashes. Four archives changed relative to candidate.4; seven shared component archives are byte-identical. Generated presentation headers have exact exported inputs and an existing generator reproduction procedure. Current build notes take precedence over retained historical notes and old in-app source-map annotations.

Candidate.5 uses the same native build lanes and numeric flags; descriptive VERSION_ADDITIONAL is BAR-0.17.0-candidate.5 and both sync identities remain unchanged. No native rebuild is performed during publication. Legal notices and dependencies are retained. Private logs, account information, settings and game data are excluded.

Source correspondence and CPU/package checks do not prove clean-machine or bit-for-bit rebuilding, full multiplayer synchronization, new graphical acceptance or measured performance. See the release validation scope and exported build context for the limits. AI tools assisted this implementation.
