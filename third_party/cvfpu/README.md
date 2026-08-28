# CVFPU / FPnew vendoring note

This directory contains the synthesizable FPnew sources from
`openhwgroup/cvfpu` commit `355c388ed0899643d41194aed22d3bd2c09e84b3`
(repository `develop` head on
2026-08-26).  The core is configured by this project for RV32D and is licensed
under the Solderpad Hardware License 0.51.  The bundled T-Head divide/square-root
sources retain their Apache-2.0 notices.

Only the source and vendor files required by `fpnew_top` are copied here.
Upstream: https://github.com/openhwgroup/cvfpu
