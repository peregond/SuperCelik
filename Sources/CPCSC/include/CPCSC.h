// Re-exports Apple's PC/SC headers so Swift can import them (the system `PCSC`
// module is not importable from Swift: "incompatible with feature 'swift'").
#ifndef CPCSC_H
#define CPCSC_H

#include <PCSC/wintypes.h>
#include <PCSC/pcsclite.h>
#include <PCSC/winscard.h>

#endif
