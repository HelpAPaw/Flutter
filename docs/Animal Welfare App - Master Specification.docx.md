**ANIMAL WELFARE**  
**PEER-TO-PEER SUPPORT APP**

Master Product Specification

*A structured coordination system that turns scattered compassion into organised action.*

Consolidated and reorganised from the full project ideation notes.  
Structured to follow the agreed Recommended Document Order.

By Leah Spasova

**Contents**

# **1\. Product Vision**

## **1.1 Working Name**

Placeholder until decided.

## **1.2 One-Sentence Description**

A peer-to-peer animal welfare case-management platform that helps everyday people report, rescue, foster, rehome, support, and coordinate help for animals in need.

## **1.3 Core Mission**

To replace chaotic Facebook-group animal rescue activity with a structured, transparent, action-based platform where community members can organise practical help for stray animals and owned animals needing rehoming.

## **1.4 Background and Origin**

The project grows out of a Facebook group set up 16 years ago for people in Bulgaria to help one another save, rescue, adopt, and fundraise for the medical bills of stray animals, mostly cats and dogs. The community has grown steadily because peer-to-peer support in Bulgaria is substantial, while municipalities and government are seen as ineffective in this area. Several earlier attempts to build a dedicated app (with a Bulgarian developer, and separately with a team in India) did not progress far. The aim now is to define a detailed, robust specification for an app that can serve the full needs of the animal welfare community in Bulgaria and in many other countries.

## **1.5 Primary Audience**

Everyday community members and volunteers in Bulgaria, including locals and foreign residents who want to help animals.

## **1.6 Initial Animal Scope**

Cats and dogs first. Other animals can be added later.

## **1.7 Platform Philosophy**

Not a social network. Not a fundraising/payment platform. Not an NGO-only tool. It is a community-led animal welfare case-management system.

More broadly, the platform should be treated less like an app idea and more like a full animal welfare infrastructure platform: part rescue coordination tool, part public reporting system, part adoption/fostering marketplace, part fundraiser, part community governance system, and part advocacy platform.

## **1.8 Module Evaluation Framework**

The plan is broken into modules. For each module, the following are defined:

* What problem it solves.

* Who uses it.

* What the user can do.

* What moderators/admins can do.

* What data is collected.

* What risks/abuse cases exist.

* What costs it creates.

* What can be built in MVP versus later versions.

***Rationale:** This section sets the direction so the app does not become a messy pile of good ideas with no clear spine.*

# **2\. Product Principles**

These are the non-negotiables.

## **2.1 No Facebook-Style Feed**

Users should not be dropped into an endless tragedy feed. They choose what they want to browse or help with.

## **2.2 Action-Based, Not Scroll-Based**

The main platform is built around cases, needs, filters, alerts, and helper matching.

## **2.3 Full Transparency for Public Posts**

No anonymous public case posting. People post under real names with visible profiles.

## **2.4 Protected Abuse Reporting**

Animal abuse/neglect/legal reports are not public by default. They go into a protected admin/authority workflow.

## **2.5 Cost-Controlled by Design**

No infinite scroll, optional map loading, image compression, limited uploads, and no video uploads in the MVP.

## **2.6 Humane for Humans Too**

Sensitive media is blurred, users can control what they see, and under-18 users are protected from graphic content. The platform should help animals without constantly traumatising the humans trying to help them.

## **2.7 Community-Led First, Institutions Later**

NGOs, vet clinics, municipalities, animal hotels, and safe houses are important later-stage entity users, but the MVP is for everyday people first.

## **2.8 Guiding Strategic Filter**

The app should not be built as Facebook for animal rescue. It should be built as a structured coordination system that turns scattered compassion into organised action. Every feature should answer at least one of these questions:

* Does this help an animal get rescued faster?

* Does this help people coordinate better?

* Does this reduce confusion?

* Does this increase trust?

* Does this protect vulnerable animals?

* Does this reduce fraud?

* Does this help fosters, adopters, rescuers, vets, and donors work together?

* Does this help the platform survive financially?

***Rationale:** This gives a strong filter for every idea.*

# **3\. User Roles and Profile Types**

This area separates platform power (permission roles) from user identity (profile/helper tags). One person may be a rescuer, foster carer, adopter, donor, transport volunteer, and lactating-animal contact all at once, so identity must be flexible while permissions stay simple.

## **3.1 Permission Roles**

These decide what powers someone has in the platform.

### **Community Member**

Everyday user who can browse, post cases, comment, message, report issues, offer help, pledge support, apply to adopt/foster, create general fundraisers, post adoption/rehoming cases, submit abuse reports, and update their own cases.

### **Moderator**

Trusted volunteer/community safeguard who can review reports, lock comments, mark media sensitive, flag behaviour, apply moderation labels, restrict users, request corrections, hide posts temporarily, escalate emergency broadcast requests, and escalate serious issues to admins.

### **Admin**

Higher-level operational user who can ban users, review serious reports, manage abuse/legal reports, restrict users, approve/deny appeals within their authority, manage moderators, communicate with NGOs/municipalities, export authority reports, assign cases to moderators, and view private feedback on moderators/municipalities.

### **Super Admin / Platform Owner**

Full backend access, regional permission control, API/storage oversight, system settings, role management, highest-level appeals, payment/fundraising rules, legal/compliance settings, and final platform-wide governance authority. (The Super Admin and Platform Owner roles are distinguished in detail in section 3.5.)

***Rationale:** Roles should be about platform power, not identity. Defining roles early prevents chaos, because animal welfare communities attract both incredible helpers and highly emotional, conflict-prone situations.*

## **3.2 Profile Identity Tags (Helper Tags)**

These are self-selected or verified labels that describe how someone participates. They are not roles. Tags should be searchable by location, for example: People near Plovdiv who can foster kittens; Transport volunteers between Sofia and Varna; Someone with a lactating cat near Burgas; Emergency foster for small dog near Ruse.

Tag list:

* Rescuer

* Foster carer

* Emergency foster

* Long-term foster

* Transport volunteer

* Driver with car

* Driver with van

* Can help with cats

* Can help with dogs

* Can bottle-feed kittens

* Can bottle-feed puppies

* Has lactating cat

* Has lactating dog

* Can take orphaned babies

* Can trap animals

* Has trap/cage

* Can help with vet visits

* Can help with fundraising

* Can photograph animals

* Can write adoption posts

* Can translate posts

* Can temporarily hold animal

* Looking to adopt

* Looking to foster

* Experienced with medical cases

* Experienced with fearful animals

* Experienced with large dogs

* Experienced with newborn kittens/puppies

Tag governance rules:

* Tags are controlled, not user-created; users can suggest missing tags to admins.

* Tags should be species-specific where useful.

* Tags should include availability, help radius, temporary availability, type of help, and species/age/needs experience.

* Inactive helper profiles are hidden from search only after 6+ months.

* Users with behaviour concerns are deprioritised in search, not removed automatically.

* Moderators can flag unsafe tag use; admins can remove/suspend helper tags after evidence and multiple reports.

***Rationale:** The tag system could become one of the most powerful parts of the app, because it turns scattered goodwill into a searchable rescue resource network.*

## **3.3 Participant Types and Typical Activities (reference)**

Earlier exploration described these participant types. They are now expressed through the unified role \+ helper-tag model, but the activities remain a useful reference for what each kind of participant can do:

* **Public user / community member:** report animals, comment, offer help, donate, share, apply to adopt, apply to foster, attend events, report abuse.

* **Rescuer / volunteer:** mark themselves as going to help, update rescue status, request transport, request foster, upload evidence, coordinate with others.

* **Foster carer:** create a foster profile, list availability, specify animal types they can take, receive requests, give updates.

* **Adopter:** browse animals available for adoption, apply, upload documents, go through screening, leave adoption updates.

* **NGO / shelter:** manage multiple animals, fundraising campaigns, adoption listings, volunteer requests, events, and a verified organisation profile.

* **Vet / clinic:** verified profile, offer discounts, verify treatment estimates, upload invoices, confirm medical cases.

* **Transport volunteer:** list routes, cities, vehicle type, distance they can cover, availability.

* **Municipality / official body (later):** receive structured reports about stray populations, abuse cases, neutering needs, or hotspots.

## **3.4 Account Registration and Identity Rules**

### **3.4.1 Required Basic Profile Fields**

Before browsing or posting, users must complete:

* Real name

* Profile photo

* Location

* Social profile link (publicly visible)

* Phone verification (in backend)

* Animal experience

* Helper tags

* Bio

* Availability

* Help radius / transport radius (for example 50 km, 100 km, nationwide)

* NGO affiliation (if applicable)

Identity matching: the app should require at least one social network profile (Facebook, LinkedIn, Instagram, or similar) to match the person.

### **3.4.2 Public Identity Rules**

* No public pseudonyms.

* No anonymous public animal/case posts.

* Social profile links are visible publicly.

* Users cannot hide required profile parts.

### **3.4.3 Activity Visibility**

Profiles show broad last-active windows only, such as: active in the last 8 hours; active in the last 24 hours; active this week. No minute-by-minute tracking.

### **3.4.4 Banned Users**

Banned users should be prevented from rejoining via phone/social profile matching for at least six months.

### **3.4.5 Under-18 Users**

Under-18 users may be allowed with restrictions. They cannot view sensitive/gory/traumatic media and must agree to this before using the platform.

## **3.5 Profile Types**

### **3.5.1 Community Member Profile**

Includes identity, helper tags, availability, contribution stats, reviews, and current/recent case activity. Stats should include:

* Cases posted

* Cases helped

* Transports completed

* Foster involvement

* Adoption involvement

* Public verified donations

* Reports submitted

These stats remain even when old cases are deleted or archived (stats do not require the public case to remain visible).

### **3.5.2 Adopter Profile Section**

Required before someone can publish a "seeking a pet to adopt" post. Fields:

* Type of home: house, flat, farm, other

* Own or rent

* Landlord permission (if renting)

* Is the home safe for the animal?

* Balcony/window safety

* Garden/yard access

* Fenced outdoor space

* Desired species

* Desired age

* Desired size

* Existing pets

* Children in the home

* Previous animal/adoption experience

* First-time adopter or experienced adopter

* Work schedule / time animal may be alone

* Indoor/outdoor plans

* Willingness to neuter/spay

* Willingness to vaccinate and provide vet care

* Willingness to sign adoption agreement

* Openness to follow-up

* Openness to home check (if requested)

* Willingness to adopt senior/special-needs animals

* Preferred region and willingness to travel

**Earlier exploration also listed adopter application fields:** experience with animals, home type, other pets, children, work schedule, indoor/outdoor plans, vet reference, agreement to neutering/care requirements, and consent to follow-up.

### **3.5.3 Foster Profile Section**

Required for people presenting themselves as foster carers. Fields:

* Species accepted

* Size accepted

* Gender accepted/restricted (if relevant)

* Age range accepted

* Medical cases accepted or not

* Emergency foster availability

* Long-term foster availability

* Current capacity

* Capacity public or hidden

* Available/unavailable status

* Isolation space (optional)

* Other pets (optional)

* Children (optional)

* Foster radius/location

Foster capacity is public unless hidden by the user.

**Earlier exploration also listed foster profile fields:** city/region, number of animals they can take, experience level, can handle medical cases, can bottle-feed kittens, can handle large dogs, can isolate animals, has other pets, has children, transport available, verification status, and reviews/history.

### **3.5.4 Later-Stage Entity Profiles**

These are not MVP core but should be designed into the architecture. (See section 19 for the full entity-expansion rules.)

#### ***NGO Profile***

Verified badge, document verification, multiple staff accounts, ability to post on behalf of the organisation, manage many cases, and show a filterable post history.

#### ***Vet Clinic Profile***

Verified clinic profile, public participation required if verifying fundraisers, ability to verify medical cases, bills, payments, treatment status, and comment publicly on medical cases.

#### ***Municipality / Authority Profile***

One verified parent municipality account with department accounts underneath, each with a named responsible person. Can receive reports, update statuses, and state local evidence/form requirements.

#### ***Animal Hotel / Safe House Profile***

Directory-style listing with location, prices/from-prices, capacity, emergency availability, reviews, owner/manager, and ability to receive emergency placement requests.

## **3.6 Platform Governance Roles**

The app should have a clear hierarchy of authority, responsibility, and backend access. Each role is defined not only by what someone can do, but by how much trust, oversight, and operational responsibility they carry.

### **3.6.1 Moderator**

Moderators are volunteer community safeguarders who keep the platform functional, safe, and organised at the case/community level.

**Typical powers:** review user reports; flag problematic behaviour; apply moderation labels; mark media as sensitive; lock comments; hide or escalate problematic posts; report suspected misuse to admins; review Red Alert misuse; identify duplicate posts; escalate suspicious fundraising; escalate abuse/neglect reports; request emergency broadcasts from admins.

**Limits:** no full banning power, no full backend access, no API access, no payment/system access, and no authority to make platform-wide decisions.

***Rationale:** Moderators are the first line of community safeguarding, but they should not have unchecked power.*

### **3.6.2 Admin**

Admins sit above moderators. They may also be volunteers, but carry greater responsibility and broader operational powers. Admins can be regional, with one admin overseeing a group of moderators in a specific region, municipality, or cluster of areas.

**Typical powers:** oversee several moderators; manage regional moderation issues; restrict users; ban users; review serious behaviour records; handle appeal reviews within their authority level; review suspicious fundraising; review serious Red Alert misuse; manage abuse/neglect report workflows; communicate with NGOs and municipalities; export structured reports for authorities where appropriate; assign cases/reports to moderators; review private feedback about moderators and municipalities.

**Limits:** no control of system-wide technical settings, APIs, integrations, billing infrastructure, or full backend configuration.

***Rationale:** Admins are regional or operational leaders, with more power than moderators but still limited by audit logs and higher oversight.*

### **3.6.3 Super Admin**

Super admins are a separate level above admins. These could eventually become paid professional roles, especially if the platform scales nationally or internationally. They may oversee large regions, national sections, specialist workflows, or high-risk operational areas such as abuse reporting, fundraising integrity, moderator oversight, or institutional partnerships.

**Typical powers:** oversee multiple admins; manage regional permission structures; handle escalated appeals; review repeated moderation disputes; review high-risk behaviour cases; oversee sensitive reports; audit admin/moderator actions; manage entity verification workflows; oversee high-risk fundraisers; intervene in major platform safety issues; supervise national/regional operations.

**Limits:** should not be the same as the platform owner; may have high-level operational control but not necessarily full backend/API/integration access. Should not automatically have access to API keys, billing systems, full database controls, infrastructure settings, owner-level system configuration, complete technical integrations, or platform-wide commercial/legal controls, unless specifically granted.

***Rationale:** Super admins are senior operational authorities, ideally paid as the platform grows, but they are not the ultimate technical or ownership authority.*

### **3.6.4 Platform Owner**

The platform owner is the ultimate overseer of the whole platform and must remain distinct from super admin, because the owner carries final responsibility for the product, backend, infrastructure, integrations, governance model, and platform direction.

**Ultimate access to:** full backend; API connections; integrations; system-wide settings; user-role architecture; database-level visibility; storage and API usage; billing and infrastructure; security settings; commercial/monetisation controls; platform-wide governance decisions; final escalation authority; final say on super admin/admin/moderator permissions.

**Responsibilities:** protecting the integrity of the platform; defining the governance model; making final strategic decisions; ensuring sustainability; overseeing technical and operational risk; ensuring no role has unchecked power; ensuring audit trails and accountability systems exist.

***Rationale:** The platform owner is the final authority and ultimate system controller, while super admins are senior operators within the system.*

### **3.6.5 Clean Hierarchy**

| Level | Role | Summary |
| :---- | :---- | :---- |
| 1 | Platform Owner | Ultimate authority; full backend/system/API control; final governance power. |
| 2 | Super Admin | Senior operational authority (possibly paid); oversees large regions or high-risk functions; not automatic owner-level backend access. |
| 3 | Admin | Regional or operational lead (may be volunteer); oversees moderators; handles bans/restrictions/escalations. |
| 4 | Moderator | Volunteer community safeguard; reports, labels, comment locks, escalations, frontline moderation. |
| 5 | Community Member | Everyday user: posts, helps, adopts, fosters, donates externally, reports, comments, participates. |

### **3.6.6 Governance Principle**

No role should be defined only by title. Each role should be defined by: what they can see; what they can edit; what they can restrict; what they can escalate; what they can export; what they can never access; who audits their actions; and who can overrule them. This prevents the platform from becoming dependent on informal trust alone.

# **4\. Main Case System**

This is the heart of the app. Every animal in need becomes a structured case, not a random post. Everything else — rescue, funds, foster, adoption, moderation, search, and backend — connects to it.

## **4.1 Every Animal-Related Action Post Is a Case**

The app should require users to choose a structured post type before posting, then fill in required fields, so people cannot publish useless posts like "help this dog" with no location, no status, and no next step. Core case/post types:

* Animal needs rescue

* Animal needs foster

* Animal needs adoption

* Owned animal needs rehoming

* Animal needs medical care

* Medical bill fundraiser

* Animal needs transport

* Animal needs funding (general)

* Babies need lactating mother

* Bottle-feeding support needed

* Lost animal

* Found animal

* Abuse or neglect concern

* Food / supplies needed

* Volunteer help needed

* Local danger warning

* Seeking a pet to adopt

* Success / update story

General advice and questions belong in the forum (section 15), not the case system. Warning/scam alerts and resource posts may also be carried as appropriate post types or in the forum.

***Rationale:** Structured posting is one of the biggest upgrades over Facebook groups; it makes posts less emotionally free-form but far more useful for coordination and search.*

## **4.2 Case Architecture**

Each case has one main category and multiple secondary help-needed tags, ordered by priority (most urgent need now, next need, later need). As needs are resolved, the case holder removes/completes tags and the next priority becomes active. Example priority path:

* Rescue needed

* Vet care needed

* Foster needed

* Medical fundraising needed

* Adoption needed

Each case also carries: a main category; secondary help-needed tags with priority order; location; urgency level; case holder; status; timeline; comments; media; reports; followers; and involved helpers.

## **4.3 Case Data Fields**

A case record can include:

* Animal type: cat, dog, other

* Status (see 4.7)

* Location: exact, approximate, or hidden

* Urgency level

* Photos and videos

* Description

* Date and time spotted

* Reporter

* Assigned helpers

* Current responsible person (case holder)

* Required help types

* Updates timeline

* Fundraising status

* Adoption status

* Moderator notes

* Verification status

Possible help tags include:

* Needs immediate rescue

* Needs vet care

* Needs foster

* Needs transport

* Needs food

* Needs trap/cage

* Needs funds

* Needs adoption

* Needs temporary holding

* Needs legal/police report

* Abuse suspected

* Neutering needed

* Mother with babies

* Lost/found animal

## **4.4 Required Case Fields**

Each post type should have required fields. Incomplete cases save as drafts but do not publish. Universal required fields:

* Location

* Animal type

* Case type

* Urgency level

* Description

* Photo (where possible)

* Current status

* What help is needed

* Contact/communication pathway

* Whether exact location is safe to show

## **4.5 Case Ownership**

* The original poster becomes the initial case holder.

* Case ownership can be transferred if someone else takes responsibility.

* Ownership history is visible in the case timeline; the original poster and previous case holders remain visible.

* The current case holder can update status.

## **4.6 Case Timeline**

Every case has a timeline. Every status change requires an update note. The timeline records:

* Case created

* Main category chosen

* Urgency selected

* Status changes

* Update notes

* Case ownership transfers

* Helpers involved

* Vet/NGO/clinic updates

* Fundraising changes

* Closure/resolution

* Reopening (if needed)

## **4.7 Case Statuses**

Status is separate from urgency. Each case carries a practical status.

### **Open case statuses**

* Newly reported

* Needs rescue

* Needs foster

* Needs adoption

* Needs vet care

* Needs transport

* Needs funding

* Needs lactating mother

* Needs bottle-feeding support

* Needs food/supplies

* Needs trap/capture

* Needs temporary holding

* Lost animal

* Found animal

* Abuse/neglect concern

* Under observation

### **In-progress statuses**

* Someone is checking

* Rescue in progress

* Transport arranged

* Foster arranged

* At vet

* Fundraising active

* Adoption applications open

* Adoption trial in progress

* Waiting for update

* Moderator review

### **Closed / resolved statuses**

* Rescued

* In foster

* Adopted

* Reunited with owner

* Returned to colony/location

* Transferred to NGO/shelter

* Medical treatment completed

* Case resolved

* Duplicate case

* False report

* Animal not found

* Animal deceased

* Closed by moderator

* Closed by original poster

***Rationale:** Status tags keep the community from wasting energy on cases that are already solved, outdated, duplicated, or unclear.*

## **4.8 Rescue Coordination Workflow**

This is where the app becomes more useful than Facebook. For each case, users should be able to say:

* I am going to check

* I can transport

* I can foster

* I can donate

* I can contact a vet

* I can take photos

* I can feed

* I can trap

* I can help tomorrow

* I cannot go anymore

Important coordination features:

* "Someone is on the way" status

* Time-stamped volunteer commitments

* Automatic reminders

* Backup helper requests

* Case update timeline

* Escalation if nobody responds

* Ability to close or resolve a case

* Ability to mark rescue as unsuccessful

* Ability to reopen a case

***Rationale:** Rescue coordination should reduce duplicated effort, confusion, and the classic Facebook problem of 50 people commenting but nobody actually going.*

## **4.9 Lost and Found Animals**

Lost and found is a case flow that brings everyday users into the app beyond rescue activists alone. Features:

* Report lost animal

* Report found animal

* Upload photos

* Last seen location

* Date/time

* Contact options

* Microchip status

* Reward (if any)

* Printable poster generator

* Share to Facebook groups

* Nearby match suggestions

* Alerts to users in area

* Mark reunited

## **4.10 Case Expiry and Archiving**

* Old posts expire/archive after around six months.

* Closed cases remain searchable for around three months.

* Closed-case images are reduced in quality.

* Old media may be deleted after six months or one year.

* Profile-level stats remain after case deletion/archive.

# **5\. Urgency System**

Urgency level is separate from case status. A traffic-light system is used.

## **5.1 Traffic-Light Levels**

### **Green — Under Control**

The animal is not in immediate danger, or the situation is being managed. Examples: animal is safe but needs adoption; foster is secured but funds are still needed; cat is fed regularly and monitored; rehoming is needed but not urgent.

### **Amber — Support Needed ASAP**

The situation needs quick help but is not necessarily life-or-death within minutes or hours. Examples: animal needs foster by tomorrow; transport is needed soon; vet appointment is needed urgently; food/shelter support is needed; puppies/kittens need help soon but are temporarily safe.

### **Red — Immediate Critical Help Needed**

Only for situations where serious harm, death, disappearance, or immediate danger may follow if help does not happen now. Examples: animal is injured on the road; animal is trapped; newborns are dying or exposed; abuse is happening now; animal is in immediate danger from traffic, poisoning, freezing, heat, aggression, or removal.

## **5.2 Red Alert Rules**

* Only the original poster/case holder, a moderator, or an admin can mark a case Red.

* No case type is automatically blocked from Red (not even general adoption posts), but the case must still meet Red Alert criteria.

* Red Alert requires a mandatory confirmation pop-up.

* Red Alert requires specific fields: location, immediate danger, last seen, whether someone is going, contact availability, current status.

* There is no special Red Alert limit for new users.

* Red Alerts publish immediately.

* Users can report Red Alert misuse.

* If not updated, a Red Alert becomes "needs update" after around 5–6 hours.

* If still not updated, it can downgrade/expire after 24–48 hours.

* Repeated misuse (over at least three months) is tracked in behaviour history and visible to moderators.

* Users can opt out of Red Alert notifications.

### **5.2.1 Mandatory confirmation**

Before publishing a Red Alert, the user must see a confirmation message to the effect of: Red Alert is only for critical cases where the animal may die, disappear, be seriously harmed, or remain in immediate danger if help does not happen now. Misusing Red Alert reduces trust in the system and may affect your account. The user must then tick a confirmation such as: I understand and confirm this is an immediate critical case.

***Rationale:** Red Alert must be protected, because if people overuse it the whole urgency system becomes meaningless and help is distracted away from animals truly at risk.*

## **5.3 Misuse of Urgency Labels**

Users should be able to report:

* Red Alert used for a non-critical situation

* Amber used when the case is already under control

* Misleading urgency

* False emergency

* Emotional exaggeration

* Repeated misuse by the same user

Moderator actions for urgency misuse:

* Downgrade urgency level

* Add moderator note

* Ask user to clarify

* Warn the user

* Apply behaviour points

* Temporarily restrict ability to use Red Alert

* Require moderator approval before future Red Alerts

* Escalate repeated misuse to admin

# **6\. Location System**

Location is powerful but potentially expensive and risky, so it must be designed carefully.

## **6.1 Every Post Has a Location**

No current post type works without location.

## **6.2 Exact vs Approximate Location**

Location display is controlled by case type and user choice; approximate location is not the default. The app should ask:

* Is exact location needed?

* Is exact location safe to publish?

* Are you sure you want to publish exact location?

Adoption/rehoming posts should generally use region/approximate location, not a home address.

Design considerations raised for location handling: Google Maps versus OpenStreetMap/Mapbox alternatives; exact versus approximate location; when location should be hidden to protect animals; whether users can create pins freely; whether map pins expire after a period; how many map loads happen per user; whether map view loads only when clicked; whether clustering is used to reduce API calls; whether moderators can obscure sensitive locations.

## **6.3 Map Cost Control**

* Users browse by region/list first.

* The map loads only when the user clicks "View Map".

* The map is optional, never the default.

* Case cards show distance/radius (within the chosen radius) without loading the map.

## **6.4 Map Categories**

When the map is opened, pin categories could include:

* Animal in need

* Feeding station

* Foster available

* Vet clinic

* Shelter / NGO

* Lost animal

* Found animal

* Abuse hotspot

* Neutering campaign

* Adoption event

***Rationale:** The map could make the app incredibly useful, but it must be designed carefully because it can become expensive and can endanger animals if exact locations are exposed.*

# **7\. Search, Browsing, and Dashboard Structure**

The app must not look like Facebook and must not have a default feed. The interface asks users which area they want to browse and what kind of cases, so people are not overwhelmed by constant tragedy and are instead empowered to take proactive action. This also minimises API costs and fatigue.

## **7.1 No Default Feed**

After login, users choose what they want to do. Possible menu options:

* Browse cases

* Post an animal/case

* Urgent cases

* My Dashboard

* Cases matching my helper profile

* What’s On

* Helper Directory

* Forum / Community Board

Design principle: the app should avoid becoming just another chaotic group feed. Users select a structured post type first, then fill in required fields.

## **7.2 Filter-First Browsing**

The home screen forces users to choose filters before seeing posts. The default view is "near me", and users can save default browsing preferences. Filters:

* Near me

* City

* Municipality

* Region

* Whole country

* Case type

* Animal type

* Help needed

* Urgency

* Time window

* Status

* Verified/clinic-linked (if relevant)

Additional search/filter options raised: location; animal type; urgency; help needed; status; date posted; verified only; foster needed; adoptable animals; medical fundraisers; transport needed; nearby cases; organisation; moderator-approved cases.

Time filters:

* Today

* Last 24 hours

* Last 3 days

* Last week

* Last month

* Last 2 months

* Custom

Example: a user with an open fostering space could choose the Sofia area and the foster filter to see fostering posts nearby; or choose "from anywhere" plus foster to see calls for fostering support across the country.

**No infinite scroll.** Map view is optional and loads only when the user clicks "View Map". Case cards show compressed thumbnails until opened. Old cases can be hidden or pushed to the end, but remain searchable until expiry/deletion.

***Rationale:** Alerts and filters turn the app from passive scrolling into practical action.*

## **7.3 Dashboards**

Two distinct concepts are kept separate, because "my current responsibilities" and "possible things I could help with" should not be mixed together.

### **My Dashboard**

Cases the user owns, follows, is involved in, has committed to helping with, has commented on, or is actively tracking.

### **Matching / Discovery Area**

Cases that match the user’s helper tags, location, saved filters, and alert preferences.

### **National Urgent Cases**

A separate view for urgent Amber/Red cases across the country.

# **8\. Sensitive Media and Emotional Safety**

Animal rescue content can be distressing, so media handling must protect both animals and the humans trying to help them.

## **8.1 Upload Flow**

Every media upload asks: "Does this show injury, blood, death, severe neglect, or distressing content?" If the user answers yes, the media is automatically marked sensitive.

## **8.2 Sensitive Media Rules**

* Users are required to mark media as sensitive before upload (answering yes to the prompt auto-marks it).

* Sensitive media is blurred by default.

* Moderators can override and mark media as sensitive.

* Sensitive media can appear in public preview cards, but blurred (it is not banned from preview cards).

* Red Alerts show blurred thumbnails.

* Deceased animals can be shown only under sensitive/blurred rules.

* Repeated failure to mark sensitive content correctly affects behaviour points.

Related content-safety measures: "sensitive content" warnings; no autoplay on videos; restrictions on graphic thumbnails; guidelines for posting injured/deceased animals; child-safe settings; memorial/respectful closure tags.

## **8.3 Graphic Videos**

Videos are blocked in the MVP (external links only — see section 20). When videos are later allowed, graphic video rules apply:

* Always marked sensitive if graphic, and blurred.

* A pop-up appears before playback to the effect of: "This video contains graphic material — are you sure you want to proceed?" The user must confirm yes/no before viewing.

* Videos require stronger restrictions than photos.

## **8.4 User Content Preferences**

Users can choose how media is shown to them:

* Show all media

* Blur sensitive media

* Hide sensitive media

* Hide videos but show blurred images

Under-18 users cannot view sensitive/gory content.

## **8.5 Abuse-Report Evidence**

There is a separate evidence upload area for abuse reports, visible only to admins (and the relevant authorities). Abuse-report media stays in the protected admin/authority workflow (see section 11).

***Rationale:** The platform should help animals without constantly traumatising the humans trying to help them.*

# **9\. Comments, Messaging, and Group Coordination**

Communication is essential but also risky, so it is structured.

## **9.1 Comments**

Every case has comments.

* Comments cannot include images or videos.

* Comments cannot include bank details.

* The original poster/case holder can pin important comments.

* Moderators can lock comments.

## **9.2 Direct Messaging**

Direct messages are open to everyone, but starting a DM is not low-effort. Beginning a conversation works like filling in a short form that is sent before the other person engages and opens the conversation. Starting a DM requires:

* Selecting a purpose/category.

* Writing a meaningful initial message (no "hi"-only messages).

* A minimum message length (around 100 characters).

DMs remain private by default. If abuse happens in DMs, users should submit evidence; only super admin/platform owner could look at the backend, and only in exceptional cases. DMs are not opened to moderators/admins simply because abuse is reported — members can be asked to submit evidence instead.

## **9.3 Blocking**

Users can block others, but only after submitting a report explaining why. Moderators receive the report but do not have to approve the block; the report exists so that behaviour can be looked into if necessary. Blocked users can still see public cases.

## **9.4 Case Group Chats**

Optional, created by the original poster/case holder. The case holder can invite others but cannot force people into a group chat. Useful for active coordination between the case holder, rescuer, foster, transport volunteer, vet clinic, or NGO.

## **9.5 Safety Warnings**

Messages should include safety warnings around: payments; adoption; meeting strangers; and sharing personal details.

# **10\. Fundraising Systems**

Fundraising is split into two distinct systems. The platform is not a payment processor and does not collect, hold, or move money.

## **10.1 General Fundraising**

General fundraising is not handled financially inside the app. The platform helps people publicise existing campaigns and find backers, but does not collect money, process payments, or track donations.

* Any user can create a general fundraiser.

* No approval is required before going live.

* Must link to an external official fundraising campaign/page (a GoFundMe-type platform); links should be specific campaign URLs.

* No bank details allowed (these belong on the external fundraiser website).

* No pledge tracking inside the app.

* No "confirmed received" tracking inside the app.

* The app acts as a visibility/advertising tool, not a payment processor.

Possible general fundraiser types: food supplies; shelter building; neutering campaigns; transport support; volunteer action day resources; NGO/community campaign; emergency local animal welfare support.

**Backend implication:** general fundraising posts need URL validation and banned-field moderation for bank details, but they do not need donation accounting.

## **10.2 Medical Bill Fundraising**

Medical fundraising is stricter because it is tied to a specific animal and vet bill.

* Must be linked to an animal case.

* Vet clinic name is mandatory.

* Invoice and estimate evidence are both required.

* Treatment purpose, goal amount, and payment route (clinic or case holder) are recorded.

* The clinic should be linked to the case and participate/verify.

When a clinic is linked to a case, it receives that case, can verify it, stays part of the case, and updates the case on a case basis. On the bill fundraising specifically, the clinic sets up or provides further evidence and can verify: the animal is in their care; the bill exists; the amount due; treatment status; payment received; and whether treatment is completed. The clinic can comment on and update the medical case publicly.

### **10.2.1 Donation visibility and verification**

All members can comment under a medical bill fundraiser stating the amount they pledged. Each donation/support entry can carry three levels of verification tags:

* Stated by donor

* Verified by case holder (the person who holds the case on the app)

* Verified by clinic

The donating person should state whether they sent money directly to the clinic or to the case holder. The app distinguishes: pledged; sent to clinic; sent to case holder; received; paid directly to clinic; verified by clinic.

Donors choose their visibility but are encouraged to be public. Only public, verified donations can be confirmed and therefore count toward the donor’s profile statistics/credibility (and earn points).

### **10.2.2 Goal and review rules**

* A medical fundraiser automatically closes when the goal is reached.

* Because it auto-closes at goal, over-funding should not occur; if more money is raised than needed, this is settled between the last donors and the clinic.

* Fundraisers over €5,000 trigger admin review.

**Earlier exploration (for reference):** originally explored in-app payment options included Stripe, PayPal, bank transfer, local Bulgarian payment gateways, and direct-to-vet payments, along with fields such as amount raised, donor list, proof of payment, and refund/surplus policy. The agreed direction is that the platform does NOT process payments; medical-fundraising money flows externally (to the clinic or case holder), and the app provides linkage, evidence, and three-way verification rather than donation accounting.

***Rationale:** Fundraising could be one of the most valuable features, but it must be built around trust, transparency, and fraud prevention from the beginning.*

# **11\. Abuse, Neglect, and Legal Reporting**

This is a protected workflow, not a public case type. Community members can log suspected or actual abuse, but it is flagged at a high level and is, in effect, a formal complaint made through the platform that can be escalated to the authorities. Reports go to admin level (not moderators), and become visible to municipalities and NGOs rather than staying as a peer-to-peer community responsibility.

## **11.1 Submission**

The reporter submits a form whose information mirrors what the authorities would ask for on their legal forms, so that when the platform links them, the authorities can act on the information. Required fields:

* Municipality/region (mandatory).

* Animal details.

* Evidence (as determined by the relevant local authority form).

* Whether the animal is in immediate danger (asked regardless of whether the authorities request it).

* Location.

* Date/time.

* Whether the authorities were already contacted.

* When they were contacted, and the response received.

* Whether the report should go to NGO, municipality/authority, or both.

* Whether the reporter shares contact details or remains anonymous.

## **11.2 Reporter Identity**

Admins can see the reporter’s identity. The reporter chooses one of two options: share my contact details, or keep me anonymous (there is no "ask me before sharing" option). Reporters are informed about the authorities’ ability to follow through: if a municipality or NGO needs more information and the reporter is anonymous, the platform cannot act as a mediator, so reporters are encouraged, where they can, to give their details to the authorities. Anonymous reporters are allowed.

## **11.3 Authority Directory**

The platform maintains a directory of responsible authorities by region. Because evidence requirements and forms can differ by municipality/local requirements, the report form can change accordingly.

## **11.4 Access and Admin Tools**

Abuse reports are never public. They are transferred to admins, with limited access for moderators (a moderator can view the case but not necessarily all the details), and onward to municipalities and NGOs as the reporter chose. Admins can:

* Review reports.

* Export a structured report PDF/email for authorities.

* Send reports to authorities and/or NGOs (the reporter chooses NGOs, authorities, or both).

* Assign reports to limited-access moderators.

* Track status.

Authorities/municipalities have an internal dashboard to receive reports, and NGOs can receive selected reports.

**Earlier exploration also listed:** private evidence storage; legal guidance resources; templates for reports to authorities; an NGO escalation pathway; a case log; and a petition/protest link where relevant. Open questions raised included who can see the accused person’s details and how to avoid vigilante behaviour.

## **11.5 Status Timeline**

Statuses:

* Submitted

* Admin review

* More information needed

* Escalated to NGO

* Escalated to municipality

* Escalated to police/authority

* Under investigation

* Resolved

* Closed

* False/malicious report

False/malicious abuse reports affect behaviour points.

***Rationale:** Abuse reporting should be powerful but tightly moderated, because unmanaged public accusations could create legal and safety risks.*

# **12\. Adoption and Rehoming**

Adoption is separate from emergency rescue cases. It is peer-to-peer, supporting direct negotiation while creating safer structure and screening.

## **12.1 Adoption Posts**

Anyone can post an animal for adoption. Owned-animal rehoming posts are not treated differently administratively. Adoption posts require all available core information, with "unknown" allowed where appropriate (especially for vaccination status and similar fields). Required fields where known:

* Species

* Age or age estimate

* Sex

* Neuter/spay status

* Vaccination status

* Microchip status (if relevant)

* Medical issues

* Behaviour notes

* Good with children

* Good with cats

* Good with dogs

* Location

* Current carer/caseholder

* Adoption conditions

**Earlier exploration also listed adoption-profile fields:** name, species/breed/size, personality, indoor/outdoor requirements, adoption fee if applicable, NGO/rescuer responsible, application button, home check process, adoption agreement, trial period, and post-adoption updates.

## **12.2 Seeking a Pet to Adopt**

Users must complete the adopter profile section (section 3.5.2) before publishing a "seeking a pet to adopt" post. Such posts can specify rough age, type of animal, big or small, cat or dog, and whether the animal must be good with children or other pets. These posts are searchable by rescuers.

## **12.3 Adoption Flow Features**

* Adoption listing

* Adopter inquiry

* Direct messaging

* Suggested questions for adopter screening

* Meeting arrangement

* Trial period option

* Adoption contract template

* In-app signature

* Upload ID (optional)

* Mark adoption as completed

* Follow-up reminders

* Post-adoption update request

## **12.4 Adoption Contracts**

* Optional but highly recommended.

* Especially encouraged before marking an animal as adopted.

* Basic template filled in-app; a copy is emailed to both parties.

* Stored in the app for around one year.

* Visible only to the involved parties plus admin/super admin.

Adoption contract templates could cover: animal details; current carer/rescuer; adopter details; neutering agreement if not already neutered; a no-resale / no-abandonment clause; a return-to-rescuer clause if the adoption fails; medical disclosure; agreement to provide care; and optional follow-up permission.

## **12.5 Adoption Follow-Up and Safeguarding**

Follow-up reminders are built in (exact schedule to be defined later — see section 24). A likely schedule:

* After 3 days: animal arrived safely.

* After 2 weeks: settling-in check.

* After 1 month: adoption still going well.

* After 3 months: final welfare follow-up.

Failed/problematic adoptions can be reported, and known unsafe adopters can be internally flagged.

***Rationale:** Peer-to-peer adoption can stay flexible while still giving people templates and guardrails that reduce bad placements.*

# **13\. Foster and Temporary Care**

Fostering needs its own structure, not just random posts. A proper foster module addresses one of the biggest bottlenecks in rescue: animals often cannot be rescued because there is nowhere safe to put them.

## **13.1 Foster Profile**

Foster carers have a dedicated profile section (see section 3.5.3 for the full field list). Capacity is visible publicly unless the user marks it as hidden, and foster carers can mark themselves as unavailable. Foster offers include species, size, gender, age, and medical-case acceptance.

## **13.2 Foster Requests**

People requesting foster care must specify:

* Animal details

* Urgency

* Expected duration

* Who pays for food

* Who pays for vet care

* Whether it is emergency or planned foster

* Supplies included or needed

* Medical needs

* Behaviour notes

**Earlier exploration also listed foster-request fields:** who remains financially responsible, and agreement terms.

## **13.3 Foster Agreements**

Foster arrangement templates should exist.

## **13.4 Foster Reviews and Safety**

Foster arrangements are reviewable, and foster failures or safety issues are reportable.

***Rationale:** A proper foster module could solve one of the biggest bottlenecks in animal rescue.*

# **14\. Events, Petitions, and What’s On**

This is the advocacy and organising layer. Petitions are kept separate from events, and events act as the umbrella over protests (a protest is one type of event). It gives the community organising power, not just emergency reaction power.

## **14.1 Events**

Events can be created directly by: moderators; admins; super admins; the platform owner; NGOs; municipalities; and vet clinics. Community members can create events too, but their events must be moderated and approved by moderators (and admins and above). Protests sit under events and also require approval.

Event types:

* Protest

* Volunteer action day (for example, getting together to build dog houses or a shelter)

* Adoption day

* Food / supplies collection

* Fundraising event

* Neutering campaign

* Community meeting

* Educational event

* Shelter-building day

**Earlier exploration also listed event/campaign types:** petition, fundraiser, municipality meeting, court/public accountability campaign, and shelter support event, plus features such as organiser, share button, donation needs, updates, and a campaign page with resources.

Events include RSVP and appear on What’s On by location, date, and event type. No special protest safety/legal disclaimer is required from the platform.

**Superseded:** an earlier idea to let users volunteer for specific roles within an event is out of scope — managing per-role volunteer sign-ups within events is not the platform’s responsibility. Events use RSVP.

## **14.2 Petitions**

* Separate from events.

* No approval required before publication.

* External links only at MVP (linking to petition websites).

* Not built as an internal petition system (an internal system is a later possibility, not MVP).

## **14.3 What’s On**

The What’s On page features events and general fundraisers by location, date, and type. People can choose location and the types of cases/activities they can help with or engage with. It includes:

* Events

* Protests

* Volunteer action days

* Adoption days

* General fundraisers

* Petitions

**Medical fundraisers must NOT appear in What’s On.** Medical fundraisers are part of animal cases (see section 10.2), not standalone listings.

# **15\. Forum / Community Board**

A separate discussion layer, not the main platform. It uses an old-school forum structure:

* Topic categories

* Threads

* Questions

* Replies

Used for: advice; care questions; local initiatives; education; and general discussion. The forum should not replace case posting. (Advice requests, resource posts, and similar general discussion live here rather than in the case system.)

# **16\. Notifications and Alerts**

Alerts and personalised notifications turn the app from passive scrolling into proactive action — for example, pinging a user that there is an animal in need in their county, since most Bulgarians drive or can find transport for a rescue.

## **16.1 Default Alerts**

Users do not have to opt in to all alerts manually. By default, based on the user’s stated location/parameters:

* Red Alerts near me — on by default (opt-out).

* Amber Alerts near me — on by default.

## **16.2 User-Selected Alerts**

All other alerts are chosen by the user:

* Foster needed near me

* Transport needed (for example, on my route)

* Lost animals near me

* Adoption matches

* Medical fundraiser / case updates

* Cases I follow

* Cases I am involved in

* Events near me

* Local danger warnings

* Cases matching my helper tags

* Abuse/protest campaign in my region

## **16.3 Delivery Channels and Controls**

Default delivery: push notifications and email. Optional (user-selectable): SMS, or in-app only. Users can set:

* Alert distance

* Quiet hours

* Repeated-notification preferences (whether to keep receiving notifications about a case they follow or are working on).

Admins can broadcast emergency alerts. Moderators can escalate a request to admins for an emergency broadcast.

# **17\. Reviews and Trust**

Trust is essential, but reviews must be designed carefully because rescue communities can be emotional, political, and conflict-heavy. A simple 5-star rating is therefore not the main trust mechanism; trust is structured and evidence-based, not just popularity-based.

## **17.1 Review Format**

Reviews use all three formats:

* Star rating

* Structured feedback

* Written review

## **17.2 Review Rules**

* Users can review after any interaction (not only confirmed interactions).

* Every review must include an interaction type.

* Negative reviews do not require evidence or moderation before publication.

* Reviews do not affect search ranking.

* Reviews are separate from internal behaviour points.

* Reviews apply to all users and user types, including community members, vet clinics, NGOs, municipalities, moderators, and admins.

Interaction types include:

* Adoption

* Fostering

* Transport

* Donation

* Vet service

* NGO interaction

* Municipality interaction

* Moderator/admin experience

* General community interaction

## **17.3 Structured Community Feedback Options**

Structured feedback can use options such as:

* Reliable communication

* Helpful volunteer

* Completed promised help

* Good foster experience

* Good adoption experience

* Transport completed safely

* Concern about communication

* Did not follow through

* Concerning behaviour

* Needs moderator review

## **17.4 Private Reviews**

Reviews of moderators, admins, and municipalities are private by default and visible only to admins / super admins / the platform owner (not to everybody). Vet clinics and NGOs can respond to reviews.

## **17.5 Verification Levels**

Verification levels:

* Email verified

* Phone verified

* ID verified

* NGO verified

* Vet verified

* Trusted rescuer

* Moderator-approved

* High-risk user (flagged internally)

## **17.6 Public Trust Signals vs Internal Behaviour Record**

Public credibility builds trust, but internal behaviour records protect the platform without turning everything into public shaming.

### **Public trust signals (visible to the community)**

* Verified phone/email

* Trusted foster

* Completed transport

* Successful adoptions

* Positive reviews

* NGO-linked account

* Long-standing member

### **Internal behaviour record (visible only to moderators/admins)**

* Abusive behaviour flag

* Fraud suspicion

* Red Alert misuse

* Harassment reports

* Adoption concern

* Animal hoarding concern

* Fundraising irregularity

* Repeated misinformation

* Moderator notes

* Behaviour points

***Rationale:** Trust tools are necessary, but reviews must be designed carefully because rescue communities can become emotionally volatile and unfairly punitive.*

# **18\. Moderation and Behaviour Records**

Moderation is not optional; animal welfare groups often deal with urgency, trauma, conflict, scams, blame, and public shaming. Moderator protocols are what will make the platform safer than Facebook.

## **18.1 What Users Can Report**

* Fraud

* Abuse

* Harassment

* False information

* Dangerous advice

* Animal endangerment

* Graphic content

* Spam

* Fundraising concerns

* Adoption/foster concerns

* Hate speech / threats

* Doxxing

* Defamation risk

* Duplicate case

## **18.2 Behaviour Categories**

Moderators can apply behaviour categories such as:

* Abusive behaviour

* Harassment

* Suspicious fundraising

* Urgency misuse

* False information

* Unsafe adoption concern

* Unsafe foster concern

* Animal hoarding concern

* Graphic content misuse

* Spam

* Duplicate posting

* Failure to update urgent case

* No-show after committing to help

## **18.3 Moderator Actions**

* Hide post

* Lock comments

* Request evidence

* Add warning label

* Merge duplicate case

* Suspend/restrict user temporarily

* Escalate to admin

* Mark fundraiser as under review

* Remove images

* Hide exact location

* Privately message user

* Add internal notes

* Create case history

Moderators can enact restrictions. Banning is an admin-level action (see 18.5).

## **18.4 Behaviour Points**

* Penalised behaviours apply automatic points when a specific behaviour is enacted and penalised.

* Current direction: behaviour points do not expire. (This is still subject to final confirmation — see section 24 — because an earlier version had minor points expiring yearly and serious points remaining indefinitely.)

An example point scale discussed: minor issue 1 point; repeated urgency misuse 2 points; harassment 3 points; fundraising concern 4 points; serious animal safety concern 5+ points; fraud or abuse goes to immediate admin review.

## **18.5 Restrictions, Reviews, and Bans**

* Automatic restrictions/reminders/processes are triggered by: abusive behaviour, harassment, and false information.

* Moderators review: false information, suspicious fundraising, and urgency misuse.

* Moderators can restrict users.

* Admins can ban users.

**Earlier behaviour-escalation ladder (for reference):** Warning 1 educational; Warning 2 restricted posting; Warning 3 temporary suspension; serious breach immediate ban; with an appeal process and moderator audit log.

## **18.6 Appeals**

* Users can appeal moderation decisions.

* Around five appeals are allowed.

* A sixth appeal within one year triggers super admin review.

## **18.7 Audit and Oversight**

* All moderator/admin actions are audit-logged.

* Users are notified when a behaviour flag is added.

* Internal behaviour records are not visible to the user.

* Moderators can also be flagged/reported and can receive behaviour points, which helps reduce moderator abuse or bias.

## **18.8 Moderator Protocols**

Moderator protocols should eventually be written as practical manuals. Protocols are needed for:

* Urgency misuse

* Duplicate cases

* Suspicious fundraising

* Abusive comments

* Harassment

* Threats

* Public accusations

* Animal hoarding concerns

* Unsafe adopters

* Unsafe fosters

* Graphic images

* False information

* Arguments between rescuers

* Doxxing

* Defamation risk

* Repeated no-shows

* People promising help and disappearing

* Users posting animals without location/details

* Owned-animal rehoming disputes

* Reports involving minors

* Reports involving authorities

Each protocol should include:

* What the moderator checks

* What label can be applied

* What message/template is sent

* What action can be taken

* When to escalate to admin

* What goes on the user’s internal record

* Whether behaviour points apply

* Whether the case remains public, hidden, locked, or edited

***Rationale:** Moderation is not optional; moderator protocols are what will make the platform safer than Facebook.*

# **19\. Entity Expansion**

Entity profiles are added later, not in the first MVP. They include: NGOs; vet clinics; municipalities/authorities; animal hotels; and safe houses. (Full entity profile field lists are in section 3.5.4.)

## **19.1 General Entity Rules**

When added, entities should have:

* Verified badges

* Multiple staff accounts

* Directory visibility

* Searchable profiles

## **19.2 Specific Rules**

* NGOs can post on behalf of their organisation.

* Vet clinics must be publicly active users if they want to verify medical fundraisers (they cannot verify while staying private).

* Municipalities cannot receive reports without participating publicly.

* Animal hotels and safe houses can list capacity (including emergency capacity), not only advertise services.

* Entities appear in case workflows only when actually engaged, and their activity is logged as part of the case.

***Rationale:** These entity users are important later-stage participants, but the MVP is for everyday people first.*

# **20\. Backend Cost Control**

Media and API costs can quietly kill the project, so cost control is designed in from the start. The app must be built to survive success: a popular free rescue app with unlimited media and maps could become financially dangerous very quickly.

## **20.1 MVP Cost Rules**

* No video uploads in the MVP (until paid tiers are introduced).

* External video links allowed instead (for example, YouTube and other video platforms).

* Videos can be introduced later, possibly with paid tiers.

* Each post allows up to two images at first.

* Paid members can upload more images; image limits differ by user type.

* All images are automatically compressed.

* Closed-case images are automatically reduced in quality.

* Old media is automatically deleted after six months or a year.

* Map view loads only when the user clicks "View Map".

* Approximate location is not the default; display is controlled by case type and user choice.

* Users browse by region/list first before opening map pins.

* AI features are avoided in the MVP unless essential.

**Earlier exploration suggested:** an alternative image policy of 3–5 images for basic users and more for verified rescuers/NGOs, with storage quotas for high-volume users. The agreed MVP direction is up to two images per post, more for paid members.

## **20.2 Cost-Control Techniques**

* Encourage links to external videos instead of hosting.

* Compress images automatically.

* Generate low-resolution thumbnails.

* Lazy-load images only when viewed.

* Set upload limits by user type.

* Use cloud storage with lifecycle rules.

* Delete duplicate images.

* Archive old cases.

* Limit the number of images per case unless verified.

* Use CDN caching.

* Avoid loading map and media at the same time.

* Use WebP image conversion.

* Only allow videos for verified users or urgent cases (later).

* Host heavy media separately from the main app server.

* Use open-source map options where possible.

* Limit unnecessary API calls.

* Use clustering on the map to reduce API calls.

## **20.3 Cost Areas to Monitor**

* Maps

* Image/video storage

* Notifications

* AI usage

* Payment processing

* Hosting

* Security

* Moderation

* Customer support

* Developer maintenance

* Legal/compliance

* Translation

## **20.4 Usage Oversight**

* Super admin/platform owner sees API and storage usage.

* Heavy users are not quota-limited, but they are flagged to super admin/owner — surfaced as stats showing who the top users are and what they post.

Cost-control principles: build a lean MVP; avoid video hosting at first; use image compression; limit unnecessary API calls; use caching; archive old content; put advanced features behind verified accounts; monitor usage by feature; build admin cost dashboards; and avoid over-engineering before adoption is proven.

***Rationale:** Media costs can quietly kill the project, so image/video rules must be designed before launch, not after the bills arrive.*

# **21\. Admin Dashboards**

## **21.1 Admin Dashboard Sections**

The admin dashboard should include:

* New reports

* Abuse/neglect reports

* Red Alerts

* Fundraisers under review

* Medical bill verification requests

* User behaviour flags

* Moderator actions

* Appeals

* Entity verification requests

* High-cost media/API usage

* Open urgent cases with no updates

* Suspicious duplicate accounts

## **21.2 Admin Abilities**

* Search all users and cases.

* Assign cases to moderators.

* See private feedback on moderators/municipalities.

* Export reports only for the purpose of communicating with NGOs/municipalities.

## **21.3 Admin Restrictions**

* Cannot impersonate users (no impersonation for support).

* Cannot set regional permissions.

## **21.4 Super Admin / Platform Owner Oversight**

Handled at super admin / platform owner level:

* Regional permissions

* API/storage usage oversight

* Full backend access

* Platform-wide system rules

***Rationale:** The backend should be designed around workflows, permissions, and accountability, not just posts and comments.*

# **22\. MVP Scope**

The biggest danger is trying to build everything at once. The MVP should solve the main coordination problem first; everything else can be layered on once the community actually uses it.

## **22.1 MVP Feature Set**

A strong MVP could include:

* User registration and profiles

* Animal case creation

* Location tagging with user-chosen location and safety controls

* Case statuses

* Help-needed tags

* "I can help" commitments

* Comments and updates

* Basic moderator dashboard

* Reporting bad behaviour/content

* Basic adoption/foster tags

* Basic fundraising link field (external links; not in-app payment processing)

* Sharing to Facebook groups

* Search and filters

* Notifications for nearby urgent cases

MVP constraints carried from the cost-control and structure decisions: no video uploads (external links only); up to two images per post; no default feed (filter-first browsing); map loads only on "View Map"; petitions as external links only; AI avoided unless essential; entity profiles (NGO, vet, municipality, animal hotel, safe house) not in the first MVP.

***Rationale:** The MVP should solve the main coordination problem first; everything else can be layered on once the community actually uses it.*

# **23\. Later-Stage Roadmap**

Features to layer on after the MVP:

* Full adoption application system

* Foster database

* Reviews

* Petitions as an internal system (beyond external links)

* Events

* Vet verification

* Entity profiles: NGOs, vet clinics, municipalities/authorities, animal hotels, safe houses

* Municipal reporting

* Video uploads, likely with paid tiers

* More images for paid members / paid tiers

* AI matching and other AI features (see section A1)

* Advanced analytics

* Expanded fundraising visibility and verification

* White-label / country licensing

* Marketplace (products and services)

**Note on in-app donations:** earlier exploration listed in-app donations as a later feature. The agreed direction is that the platform does not process payments; later fundraising work focuses on expanded visibility and the three-way verification model rather than handling money in-app.

# **24\. Open Decisions Still Needing Finalisation**

Even with a lot decided, these points remain unresolved:

* Exact behaviour-point expiry rule: no expiry vs minor yearly expiry.

* Exact adopter follow-up reminder schedule.

* Exact vet clinic verification method.

* Exact NGO document verification method.

* Accepted external fundraising URL providers.

* Whether general fundraising links need a domain allowlist.

* Whether phone verification happens at registration or before posting.

* Exact definition of "paid tiers" later.

* Whether local forums are organised by municipality, region, or both (and whether the app has in-app local/regional communities such as Sofia, Plovdiv, Varna, Burgas).

* How much of the platform must be bilingual at MVP beyond menus (Bulgaria-first with later translation, or bilingual from the start).

# **25\. Data Model and Backend Entities**

The app is not just a posting platform; it is a structured case-management and trust-management system. The backend should be designed around workflows, permissions, and accountability.

## **25.1 Major Backend Entities**

* Users

* Roles

* User profile tags

* User verification

* Public trust history

* Internal behaviour records

* Animal cases

* Animal profiles

* Animal post types

* Locations

* Help offers

* Foster profiles

* Adoption applications

* Adoption contracts

* Fundraising campaigns (general and medical)

* Donations / pledges

* Confirmed payments (verification records, not money handling)

* Uploaded invoices/proof

* Events

* Reports

* Reviews

* Moderator actions / labels

* Behaviour points

* Notifications / alerts

* Organisations

* Vet clinics

* Audit logs

## **25.2 Backend Needs / Capabilities**

* Role-based permissions

* Case status workflows

* Case urgency levels

* Case closure

* Audit trails (moderator/admin actions)

* Duplicate detection

* Notification system

* Media compression pipeline

* Fraud monitoring

* Admin dashboard

* Analytics dashboard

* API cost monitoring (maps/media/API usage)

* Data retention rules

* Location privacy controls

* Search by location/tags/status

* Comments

* Direct messages

* Fundraising goals and pledge/verification tracking

**Note on payments:** earlier exploration listed payment integration as a backend need. The agreed direction is no in-app payment processing; pledge/payment fields exist for the medical-fundraising verification workflow (donor / case holder / clinic), not for moving money through the platform.

# **26\. User Journeys**

Detailed user-journey maps are to be produced in a later pass. The core journeys are already defined by the workflows elsewhere in this document and would form the basis of those maps:

* Reporting and coordinating a rescue case (sections 4.8 and 5).

* Offering help via helper tags and being matched/discovered (sections 3.2 and 7.3).

* Fostering: offering capacity, receiving a request, and arrangement (section 13).

* Adoption: listing an animal, screening an adopter, contract, and follow-up (section 12).

* Seeking a pet to adopt (sections 3.5.2 and 12.2).

* General fundraising via an external campaign link (section 10.1).

* Medical-bill fundraising with three-way verification (section 10.2).

* Submitting and escalating an abuse/neglect report (section 11).

* Lost and found, including reunite (section 4.9).

* Moderation: report, label, behaviour points, appeal (section 18).

# **27\. Developer Build Notes**

Engineering and build considerations raised across the discussion (consolidated; details also appear in sections 6, 20, and 25):

## **27.1 Maps and Location**

* Evaluate Google Maps versus OpenStreetMap / Mapbox alternatives; prefer open-source map options where possible.

* Load the map only on "View Map"; never load map and media at the same time.

* Use clustering to reduce API calls; let moderators obscure sensitive locations.

* Browse by region/list before opening pins; consider whether pins expire after a period.

## **27.2 Media Pipeline**

* Automatic image compression and WebP conversion; generate low-resolution thumbnails.

* Lazy-load images only when viewed; use CDN caching.

* Cloud storage with lifecycle rules; reduce closed-case image quality; delete old media after 6 months–1 year.

* Delete duplicate images; host heavy media separately from the main app server.

* No video hosting in MVP; external links only.

## **27.3 Integrity and Monitoring**

* Duplicate detection for cases and accounts; fraud monitoring for fundraisers.

* API/storage cost monitoring with admin cost dashboards; usage flagged to super admin/owner.

* Role-based permissions and full audit trails for moderator/admin actions.

* Data retention rules and location privacy controls.

## **27.4 Build Discipline**

Build a lean MVP, put advanced features behind verified accounts, monitor usage by feature, and avoid over-engineering before adoption is proven.

# **Appendices**

The following sections appear in the source material but sit outside the agreed Recommended Document Order. They are retained here in full so that no information is lost.

## **A1. AI Features**

AI could be useful but should not be the central promise at first, and should be used as a helper behind the scenes rather than a replacement for rescuers, moderators, or vets. AI features are avoided in the MVP unless essential.

Possible AI features:

* Suggest post category from text/photo

* Summarise messy case updates

* Translate Bulgarian/English posts

* Detect duplicate cases

* Flag potentially fraudulent fundraisers

* Blur graphic images

* Suggest urgency level

* Create an adoption profile from notes

* Generate printable lost/found posters

* Match adopters with suitable animals

* Suggest nearby volunteers

* Help moderators prioritise reports

Risks:

* AI mistakes could endanger animals

* AI may misread urgency

* AI moderation can be unfair

* AI image analysis can be costly

* AI should assist humans, not replace them

***Rationale:** AI should be used as a helper behind the scenes, not as a replacement for rescuers, moderators, or vets.*

## **A2. Legal, Privacy, and Ethical Framework**

Because the app deals with money, animals, locations, public accusations, and distressed people, legal structure should be treated as part of the product, not an afterthought. This is especially important where the app handles: donations; ID verification; location data; abuse reports; reviews; medical invoices; adoption applications; minors using the app; and personal disputes.

Needed policies:

* Terms of use

* Privacy policy

* Donation/fundraising policy

* Refund/surplus funds policy

* Abuse reporting policy

* Review policy

* Moderator policy

* Animal welfare disclaimer

* Medical/vet disclaimer

* Location safety policy

* Data retention policy

* Community guidelines

## **A3. Metrics and Impact Reporting**

The app should be able to show real impact. Impact data helps with funding, grants, credibility, partnerships, and motivation. Track:

* Animals reported

* Animals rescued

* Animals fostered

* Animals adopted

* Funds raised

* Vet bills paid

* Transport requests completed

* Lost animals reunited

* Neutering campaigns supported

* Active volunteers

* Response times

* Regions with highest need

* Repeat rescuers

* Verified NGOs

* Abuse cases escalated

## **A4. Go-to-Market Strategy**

A major advantage already exists: a long-standing community. The app should not try to pull people away from Facebook immediately; it should make Facebook chaos more structured.

### **Phase 1 — Community Validation**

Survey the Facebook group and rescuers: What are the biggest pain points? What would they actually use? What frustrates them about Facebook? What would stop them using an app? Which features matter most?

### **Phase 2 — Closed Beta**

Invite trusted rescuers, moderators, foster carers, NGOs, vets, and transport volunteers.

### **Phase 3 — Facebook Group Integration**

Do not fight Facebook at first; use it as the funnel: create a structured case in the app; share the case link back to Facebook; keep updates in one place; let helpers commit through the app.

### **Phase 4 — Regional Rollout**

Start with one or two Bulgarian cities/regions rather than all of Bulgaria.

### **Phase 5 — NGO and Vet Partnerships**

Bring in trusted organisations to create credibility.

### **Phase 6 — Public Launch**

Promote as the practical rescue coordination tool built from years of real community experience.

***Rationale:** The app should not try to pull people away from Facebook immediately; it should make Facebook chaos more structured.*

## **A5. Monetisation Strategy**

Monetisation must be ethical and sensitive, because animal welfare communities often have little money. It should come mostly from organisations, sponsors, grants, and optional platform support — not from desperate people trying to save injured animals.

### **Free Core Use**

Reporting animals, helping, adopting, fostering, and urgent cases should remain free.

### **Verified NGO / Shelter Plans**

Organisations can pay for enhanced tools: a better dashboard; more media storage; fundraising campaigns; volunteer management; adoption application tools.

### **Sponsored Listings**

Ethical sponsors: pet food brands; vet clinics; insurance providers; pet shops; training services; microchip companies; groomers; animal transport services.

### **Premium Tools for Organisations**

CRM-style rescue management; foster database; adoption pipeline; reports and analytics.

### **Grants**

Animal welfare, civic tech, EU, local, and corporate social responsibility grants.

### **White-Label / Country Licensing**

If the Bulgarian version works, similar communities in other countries could use the platform.

### **Marketplace**

Products and services: food; carriers; cages; medical supplies; training; insurance; transport.

**Note on a donation platform fee:** an optional small transparent fee on donations (or an optional tip to support the platform) was explored, but it sits in tension with the agreed direction that the platform does not process payments; it would only be possible if/when payment handling were introduced.

***Rationale:** Monetisation should come mostly from organisations, sponsors, grants, and optional platform support — not from desperate people trying to save injured animals.*

## **A6. Planning and Document Order (reference)**

### **A6.1 Recommended Document Order (followed by this document)**

* Product vision

* Product principles

* User roles and profile types

* Main case system

* Urgency system

* Location system

* Search/browsing/no-feed UX

* Media safety

* Communication system

* Fundraising systems

* Abuse/legal reporting

* Adoption and rehoming

* Foster and temporary care

* Events, petitions, What’s On

* Forum/community board

* Notifications

* Reviews/trust

* Moderation/behaviour records

* Entity expansion

* Backend cost control

* Admin dashboards

* MVP scope

* Later-stage roadmap

* Open decisions

* Data model / backend entities

* User journeys

* Developer build notes

### **A6.2 Suggested Order for Planning Work**

* Define the vision and non-negotiables

* List user roles and permissions

* Design the animal case system

* Design rescue coordination workflows

* Design foster, adoption, and lost/found modules

* Design fundraising and trust protocols

* Design moderation and reporting protocols

* Design map/location rules and cost controls

* Design media rules and storage cost controls

* Define MVP versus later versions

* Create backend data structure and admin dashboards

* Create go-to-market plan using the existing Facebook community

* Create monetisation model

* Create legal/policy framework

* Create investor/grant/developer pitch document

***Rationale:** This order moves from purpose, to people, to workflows, to technology, to sustainability.*

can

