# 1.0.1 stack and integrated changes

The eight maintenance units and exact stack pins are retained from [1.0.0 source preparation](../2026-10-17-v1.0.0/STACK-AND-PATCHES.md) and the [detailed component/PR ledger](../../stack-records/2026-10-17/README.md). SDL/Loader/MoltenVK/Mesa/OpenAL and AI payloads are unchanged from the frozen 1.0.0 app. Mac audio remains OpenAL mixing → OpenAL CoreAudio → output device.

The 1.0.1-only implementation change is the exact new handler identity and braces around two native diagnostic logging pairs per lane. It restores the connection of existing Mac widget providers; it does not replace their graphics code, alter gameplay, change sync identities or change numerical flags. Package/native descriptive version labels are 1.0.1.
