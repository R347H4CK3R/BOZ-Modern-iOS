# Strata/Marmalade startup repair

The uploaded engine-console(1).log shows successful memory, paths, config and device initialization, then failure in s3eGetCodeHash (diagnostic label embedded-loader) and exit(0).

Strata inserts LC_ID_DYLIB before the segment commands. Three Marmalade scanners count that command without advancing their cursor, so they cannot find __TEXT sections or s3e_data. Change only their B.NE targets to the existing cmdsize-advance block. Recalculate the package seed and re-encrypt S3E data, preserving its plaintext.

Regression: executing the original ARM64 scanner fails with LC_ID_DYLIB first. The repaired binary passes section lookup, displacement, data-address and code-hash checks for original order, ID-first and ID-between-segments layouts. The test uses a nonzero ASLR slide matching the uploaded launch; dladdr, string comparison, clock and error reporting are emulated.

This verifies the reported scanner failure, not gameplay. A physical-device launch is still required. The large-asset/small-update mechanism is not implemented by this repair.
