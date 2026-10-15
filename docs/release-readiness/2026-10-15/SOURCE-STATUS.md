# Source delivery and reproducibility

This repository commit contains the reviewed launcher source and release records; the native source companions are additionally required.

The matching source download is `BAR-0.15.4-alpha.1-sources.tar.gz`, SHA-256 `a0ad89cfe60555c6ef51a5a3578ea6e5f0d200c3cf301dd9d00f46e588bd3c9a`. Its 11 source archives, populated dependency sources/patches, inventories, licenses and portable build notes were read back. The notice download SHA-256 is `6ab132f4468be62dc7e852b06ce3eff7d0461bd39e037c258b880c1e9d09112d`.

The launcher source binds to 552 frozen inputs and three reviewed fixture pins under lock `146cb4b8…`. The latest helper correction changed exactly three production files and one existing fixture from its retained predecessor; earlier renderer/packaging corrections remain cumulative. Generated output/dependencies, private state and three dormant UNKNOWN artwork files with unused sidecars are explicitly omitted. GitHub's auto-generated repository archive alone does not reconstruct the complete native stack.

| Native component | Selected source/build binding |
| --- | --- |
| Chobby Recoil | Official base `de693612…`, full 8949-entry manifest; binary `27fa06c6…` |
| bar-lobby Recoil | Official base `694e9df7…`, full 9056-entry shield-corrected manifest; binary `794ced8b…` |
| MoltenVK | Cumulative 68cc functional source with custom diagnostics compiled out, revision `0e7c41b9`, packaged SHA `aebf0df5…` |
| Mesa/Zink, SDL, Loader/Headers, OpenAL | Exact preferred-source inventories and component build/pin records included |
| Older Chobby downloader | Clean `8263d019…` source plus populated readerwriterqueue `8e7627d1…` |

Build instructions pin official Node 22.18.0/npm 10.9.3 separately from Electron 44.7.2's embedded runtime. They preserve exact source/compiler/build options, the existing repo-local overlay validator and current cleaned asset lock `fc0a4c9a…`. Source/export metadata was frozen before final runtime acceptance; [release validation](README.md) supplies the final bounded outcomes.

GPL/LGPL program/library source, applied patches/build entries, GNU font editable source and applicable notices accompany the corresponding binary download. Permissive component notices retain their original attribution. The old Chobby libgcc_s exact provider remains unverified; GCC exception conditions are assessed component-wise rather than converting that uncertainty into blanket permission or prohibition. The p7zip executable matches an upstream import tied to its collected historical Homebrew recipe/patches; the retired bottle and a fresh byte-identical compile remain unavailable. Selected native binaries retain build-path strings.

Complete corresponding-source delivery, source-to-binary binding, successful local compilation, bit reproduction and clean-machine acceptance are separate claims. No full clean-machine or universal bit-reproduction proof is asserted. The earlier [R80 checkpoint](https://github.com/yeojuny/bar-lobby-apple-silicon/blob/555e7c322e595c331a1b20207e78f2d58c720c01/docs/stack-records/r80-20261008/README.md) retains its own older patches and evidence.
