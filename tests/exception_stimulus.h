#ifndef VANDAL_EXCEPTION_STIMULUS_H
#define VANDAL_EXCEPTION_STIMULUS_H

/*
 * Controlled architectural fault stimuli for exception-acceptance images.
 *
 * Both entry points raise one vector at a known instruction and never return,
 * because the terminal policy ends the image. Only an exception test calls
 * them; the production image does not reference or link this object.
 */

/* Execute UD2 so vector 6 is delivered with ud_site as the saved RIP. */
extern void trigger_ud(void);
extern const char ud_site;

/* Execute INT3 so vector 3 proves the policy rejects an unexpected delivery. */
extern void trigger_breakpoint(void);

#endif
