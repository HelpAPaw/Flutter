/**
 * Who gets told about a new signal.
 *
 * Split out of index.ts and kept free of the Admin SDK so it can be unit
 * tested: it is the only genuinely new decision logic in the tag feature, and
 * the failure modes are all silent — too few recipients looks like a quiet day,
 * too many looks like spam, and neither throws.
 *
 * ## The rule
 *
 * Tag matching *prioritises*; it does not gate. Everyone who matches the
 * signal's needs and is within their own radius is notified. If that is fewer
 * than `minRecipients`, the next-best candidates are added until the floor is
 * met — first the matching helpers who are further away than they asked for,
 * then the non-matching neighbours, then everyone else, each group nearest
 * first.
 *
 * Matching outranks proximity because a tag is a declaration of *ability to
 * help* while proximity only declares presence. The cost is that a helper who
 * set a 10 km radius can be told about something 40 km away; that is accepted,
 * and it is why the push payload carries the distance.
 *
 * The floor is a **floor, never a ceiling**. If 500 people match, all 500 are
 * notified — it never truncates tier A.
 */

/** A candidate who has already passed the non-negotiable preference gates. */
export interface RecipientCandidate {
  uid: string;
  /**
   * Whether any of the user's helper tags overlap the signal's needs.
   */
  matchesTags: boolean;
  /**
   * Whether the signal falls inside the radius the user actually configured
   * (live-location radius or region of interest, whichever qualified).
   */
  withinOwnRadius: boolean;
  /**
   * Km from the signal to the user's nearest known position. Used only for
   * ordering within a tier. `Infinity` for a candidate with no usable position.
   */
  distanceKm: number;
}

export interface SelectionConfig {
  /** Minimum number of people to notify, when that many are available. */
  minRecipients: number;
}

export interface SelectionResult {
  /** Uids to notify, in the order they were selected. */
  uids: string[];
  /**
   * Per-tier counts, for the structured log. The floor cannot be tuned without
   * seeing how often each tier is doing the work.
   */
  tierCounts: { a: number; c: number; b: number; d: number };
  /** How many of the selected uids came from a backfill tier. */
  backfilled: number;
}

/**
 * Rank `candidates` and take everyone in tier A plus enough backfill to reach
 * `minRecipients`.
 *
 * Callers must have already dropped anyone failing a hard gate (notifications
 * off, wrong test mode, the reporter, a signal type or species they excluded).
 * This function never re-checks those — it cannot, and it must not, because
 * every remaining preference here is one the floor is allowed to override.
 */
export function selectRecipients(
  candidates: RecipientCandidate[],
  config: SelectionConfig
): SelectionResult {
  // Tier A always ships. C outranks B: see the module comment.
  const tierA: RecipientCandidate[] = [];
  const tierC: RecipientCandidate[] = [];
  const tierB: RecipientCandidate[] = [];
  const tierD: RecipientCandidate[] = [];

  for (const candidate of candidates) {
    if (candidate.matchesTags) {
      (candidate.withinOwnRadius ? tierA : tierC).push(candidate);
    } else {
      (candidate.withinOwnRadius ? tierB : tierD).push(candidate);
    }
  }

  const byDistance = (a: RecipientCandidate, b: RecipientCandidate) =>
    a.distanceKm - b.distanceKm;
  tierA.sort(byDistance);
  tierC.sort(byDistance);
  tierB.sort(byDistance);
  tierD.sort(byDistance);

  const uids = tierA.map((c) => c.uid);

  // Walk the backfill tiers in priority order, nearest first within each, until
  // the floor is met or we run out of people.
  let backfilled = 0;
  for (const tier of [tierC, tierB, tierD]) {
    for (const candidate of tier) {
      if (uids.length >= config.minRecipients) break;
      uids.push(candidate.uid);
      backfilled++;
    }
    if (uids.length >= config.minRecipients) break;
  }

  return {
    uids,
    tierCounts: {
      a: tierA.length,
      c: tierC.length,
      b: tierB.length,
      d: tierD.length,
    },
    backfilled,
  };
}
