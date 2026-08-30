# Test list

1. Provide Nix product, candidate image, and parity proof entrypoints.
2. Bind exact candidate source/lock/provider inputs.
3. Build twice cleanly and obtain identical candidate image identity.
4. Verify candidate archive, image config, manifest, and all layer digests.
5. Verify tar SHA before WSLC load.
6. Verify image ID before WSLC run.
7. Preserve foreground TTY, volumes, workdir, and zero exposed ports.
8. Keep Golden tar identity unchanged and readable.
9. Pass a physical Windows/WSLC candidate journey.
10. Prove semantic parity.
11. Prove state and persistence parity.
12. Prove destructive/failure parity.
13. Prove pre-declared paired performance parity.
14. Produce zero mandatory skips, waivers, unknowns, regressions, false success, duplicates, and lost results.
15. Require no external registry for delivery.
16. Carry and verify the exact candidate Git source bundle.
