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
    // A candidate we cannot place is not backfill material. This is someone who
    // turned live tracking off and set no region of interest, but whose stale
    // `userLocations` doc still exists — an OS permission revoked, or a stop
    // that never reached the delete. The old code could never notify them,
    // because distance was the only way in. Letting the floor reach them would
    // push on the strength of a position they explicitly stopped sharing, and
    // there is no opt-out short of turning notifications off entirely.
    if (!Number.isFinite(candidate.distanceKm)) continue;

    if (candidate.matchesTags) {
      (candidate.withinOwnRadius ? tierA : tierC).push(candidate);
    } else {
      (candidate.withinOwnRadius ? tierB : tierD).push(candidate);
    }
  }

  const byDistance = (a: RecipientCandidate, b: RecipientCandidate) =>
    a.distanceKm - b.distanceKm;

  // Tier A ships whole, so its order is presentation only, not selection.
  tierA.sort(byDistance);
  const uids = tierA.map((c) => c.uid);

  // Walk the backfill tiers in priority order, nearest first within each, until
  // the floor is met or we run out of people.
  //
  // Sorted lazily, as each tier is reached. In the common case tier A alone
  // meets the floor and none of these are touched — and on the widened path
  // tier D is both the largest and the least likely to be drawn from, so
  // sorting all three up front was work thrown away on almost every signal.
  for (const tier of [tierC, tierB, tierD]) {
    if (uids.length >= config.minRecipients) break;
    tier.sort(byDistance);
    for (const candidate of tier) {
      if (uids.length >= config.minRecipients) break;
      uids.push(candidate.uid);
    }
  }

  return {
    uids,
    tierCounts: {
      a: tierA.length,
      c: tierC.length,
      b: tierB.length,
      d: tierD.length,
    },
    // Derived rather than counted: tier A always ships whole, so everything
    // past it is backfill by construction.
    backfilled: uids.length - tierA.length,
  };
}
