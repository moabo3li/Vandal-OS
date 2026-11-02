#ifndef VANDAL_EXCEPTION_POLICY_H
#define VANDAL_EXCEPTION_POLICY_H

#include "exception_frame.h"

/*
 * Terminal policy for one delivered CPU exception.
 *
 * exception_dispatch() prints the shared diagnostic record and then transfers
 * control here; this function owns the final decision and must not return. It
 * must not modify the record, resume interrupted execution or assume another
 * exception can be recovered.
 *
 * Exactly one strong definition is linked into an image: the production policy
 * for a normal kernel or the acceptance policy from tests/ for an exception
 * test. A missing or duplicated definition fails the link by design, so no weak
 * override or fallback can hide a wrong selection.
 */
__attribute__((noreturn)) void exception_finish(const struct exception_frame *frame);

#endif
