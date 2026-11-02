# Proposal: Library Specifications as Normative Contracts

_Owners_: @TharmiganK  
_Reviewers_:  
_Created_: 2026/11/02  
_Updated_: 2026/11/02  
_Status_: Submitted  

## Summary

Every Ballerina library has a specification at `docs/spec/spec.md`, and the [library development process](library-development-process.md) treats it as the contract: "any deviation from the specification is considered a bug". In practice, most specifications are written as feature guides. They describe features by example, mix tutorials and best practices with rules, and copy API signatures that drift from the source. This proposal defines what a library specification contains, what it must not contain, where the excluded content goes, and how each feature is specified, so that a specification can actually serve as the contract.

## Goals

- Make a library specification precise enough that any behaviour can be classified as conforming or not by reading it.
- Define a single structure and a per-feature template used by all library specifications.
- Define which content belongs in the specification and which belongs in API Docs, `README.md`/`Module.md`, Ballerina by Examples (BBEs), or ballerina.io guides.
- Provide a checklist that reviewers apply to every specification change.

## Non-Goals

- Defining a formal semantics for libraries. Specifications remain prose, structured to be unambiguous.
- Changing the proposal process. Proposals still record motivation, alternatives and decisions, and the specification records the outcome.
- Mandating tooling. Linting and conformance traceability are listed under [future work](#future-work).
- Rewriting all specifications at once. Existing specifications migrate incrementally.

## Motivation

The HTTP library specification illustrates the problems, but the same patterns appear across library specifications.

1. **Behaviour is shown, not defined.** The HTTP retry section consisted of one sentence and a configuration snippet. It did not state which failures are retried, that `statusCodes` defaults to an empty list (so HTTP responses are never retried by default), that `count` excludes the initial attempt, that a `backOffFactor` of `0.0` is treated as `1.0`, or what is returned when retries are exhausted. Users had to [ask on Stack Overflow](https://stackoverflow.com/questions/78709949/how-does-ballerina-http-retryconfig-works), and the answer came from reading the implementation. The circuit breaker, failover, load balancing, cookie and caching sections have the same gaps.
2. **The most normative areas are the vaguest.** The request routing section says "Perhaps a part of the request URI can be matched, yet they won't be picked unless the longest is matched". It does not define the precedence between literal segments, path parameters and rest parameters, trailing slash and percent-encoding handling, when `404` versus `405` is returned, or which ambiguous resource declarations are rejected at compile time.
3. **Several audiences share one document.** Style advice ("Avoid caller unless you have specific requirement"), near-identical authentication examples for every combination of approach and auth type, `Config.toml` logging recipes, and long static code rule explanations sit between the rules and hide them.
4. **API signatures and doc comments are copied.** Copies of remote method signatures and their doc comments drift from the source, and the specification then contradicts the API Docs.
5. **There is no change history.** The `_Updated_` date shows when the specification last changed, but not what changed or which library version a statement applies to.

The cost is concrete: users cannot rely on documented behaviour, reviewers cannot judge whether a behaviour change needs a specification update, and a reported bug cannot be classified as an implementation bug or a specification gap without reading the code.

## Description

### 1. Document roles

Each kind of content has exactly one home. The specification is the only normative document.

| Document                       | Purpose                                                           | Audience                              | Normative |
|--------------------------------|-------------------------------------------------------------------|---------------------------------------|-----------|
| `docs/spec/spec.md`            | Observable behaviour of the library: rules, defaults, errors      | Implementers, reviewers, expert users | Yes       |
| API Docs (doc comments)        | Per-symbol reference: signatures, parameters, return values       | Users writing code                    | No        |
| `README.md` / `Module.md`      | Overview, concepts, quick start                                   | New users                             | No        |
| BBEs                           | Runnable, minimal examples of common tasks                        | Users learning a feature              | No        |
| ballerina.io guides            | End-to-end tutorials and best practices                           | Users building solutions              | No        |
| Proposals                      | Motivation, alternatives and decisions behind a change            | Owners and reviewers                  | No        |

A separate per-library guide document is not introduced. Guide content goes to `README.md`/`Module.md`, BBEs or ballerina.io, which already have owners, review processes and rendering.

API Docs must not contradict the specification. Doc comments may summarise a rule, e.g. "network-level failures are always retried", but the specification is authoritative when they differ, and the difference is a bug.

### 2. Normative language

- The key words MUST, MUST NOT, REQUIRED, SHALL, SHALL NOT, SHOULD, SHOULD NOT, RECOMMENDED, MAY and OPTIONAL are interpreted as described in [RFC 2119](https://www.rfc-editor.org/rfc/rfc2119) and [RFC 8174](https://www.rfc-editor.org/rfc/rfc8174) when, and only when, they appear in all capitals.
- Sentences without these key words that state behaviour in the present tense, e.g. "The client returns the last response", are also normative. Key words are used where the obligation or permission needs emphasis.
- Examples, notes and the overview section are informative. Notes are written as `> **Note:** ...` blockquotes.
- Behaviour that is deliberately left open MUST be marked as _implementation-defined_ (the implementation chooses and documents it) or _unspecified_ (users must not rely on it). Anything not covered by the specification is a specification gap and is reported as a bug.

### 3. Document structure

Every specification uses the following top-level structure. Sections that do not apply to a library are omitted, not left empty.

```
# Specification: Ballerina <Name> Library

_Owners_, _Reviewers_, _Created_, _Updated_, _Edition_

## Introduction            scope, conformance statement, notation (section 2 of this guide)
## Contents
## 1. Overview             informative description of the library and its concepts
## 2. Terminology          terms used with a specific meaning in the specification
## 3..N. <Features>        one numbered section per feature, using the feature template
## N+1. Security considerations
## N+2. Static code rules  (if the library ships rules)
## Changes                 revision history
## References
```

- **Overview** is limited to what a reader needs to understand the rest of the document. It is not a tutorial.
- **Terminology** defines terms such as "network-level failure" or "resource" once, and the rest of the document uses them consistently.
- **Security considerations** states the security-relevant behaviour and defaults, e.g. TLS hostname verification, request size limits, and what the library does not protect against.
- **Static code rules** lists each rule shipped by the library as a table row with the rule ID, the condition that triggers it, and its kind. The rationale, impact and remediation of each rule belong in the rule documentation, not in the specification.
- **Changes** lists normative changes per library version, newest first, e.g. `- 2.19.0: Specified the retry behaviour of the HTTP client (#2766)`. Editorial changes are not listed.

### 4. Feature template

Each feature section contains the following subsections, in this order. Subsections that do not apply are omitted. Large features may be split into subsections that each follow the template.

1. **Description** (informative): One or two sentences stating what the feature does.
2. **Configuration**: A table of every configuration field with its type, default value and meaning. The meaning MUST cover every special value, such as `0`, `()`, an empty array, or a negative number, and how out-of-range values are handled. The public record definition MAY be included when the shape itself matters.
3. **Behaviour**: Normative rules. Processing logic, such as matching, binding, retrying or dispatching, is written as numbered steps. The rules MUST cover the outcome on success, on each failure, at boundaries (first, last, exhausted, empty), and ordering where it is observable.
4. **Compile-time validation**: The conditions the compiler plugin rejects or warns about, with the diagnostic code of each condition.
5. **Errors**: The error type returned or raised for each failure condition, and whether the error is returned to the caller, logged, or results in a specific response.
6. **Interactions**: How the feature combines with other features, including the order in which they apply, e.g. "the circuit breaker wraps the retry client, so a call and its retries count as one request".
7. **Example** (informative): One minimal example that illustrates the rules. Examples demonstrate the rules and never replace them.

The following is an abridged section written using the template.

````markdown
### 5.4. Retry

#### 5.4.1. Description
The client resends a request when it fails, waiting between attempts.

#### 5.4.2. Configuration
| Field             | Type      | Default | Meaning                                                                                                   |
|-------------------|-----------|---------|-----------------------------------------------------------------------------------------------------------|
| `count`           | `int`     | `0`     | Number of retries after the initial attempt. `0` disables retrying.                                       |
| `interval`        | `decimal` | `0`     | Wait time in seconds before the first retry.                                                              |
| `backOffFactor`   | `float`   | `0.0`   | Multiplier applied to the previous wait time. A value less than or equal to `0.0` is treated as `1.0`.    |
| `maxWaitInterval` | `decimal` | `0`     | Upper bound in seconds for wait times computed using `backOffFactor`. `0` is treated as `60`.             |
| `statusCodes`     | `int[]`   | `[]`    | Response status codes on which the request is retried.                                                    |

#### 5.4.3. Behaviour
1. The client sends the request.
2. If the attempt fails with a network-level failure, or returns a response whose status code is in `statusCodes`, and fewer than `count` retries have been made, the client waits as specified in rule 4 and goes to step 1.
3. Otherwise, the client returns the response or the error of the last attempt.
4. The wait time before the first retry is `interval`. The wait time before each later retry is the previous wait time multiplied by `backOffFactor`, capped at `maxWaitInterval`.

#### 5.4.4. Interactions
- The client `timeout` applies to each attempt separately.
- When a circuit breaker is configured, it wraps the retry client, so a call and all its retries count as one request.

#### 5.4.5. Example
...
````

### 5. Writing rules

1. Specify observable behaviour, not implementation. Class names, internal functions and data structures do not appear unless they are part of the public API.
2. Do not copy signatures or doc comments from the source. Refer to the symbol by name, e.g. `http:Client` `get` method, and specify the behaviour that a signature cannot express.
3. Do not include recommendations, best practices or tutorials. Rules that are security-relevant are stated as rules, e.g. "the listener MUST reject a request whose header section exceeds `maxHeaderSize`", in the relevant feature section or in security considerations.
4. Do not repeat an example for every combination of options. One example per feature is sufficient, and variations go to BBEs.
5. Use the terms defined in the terminology section consistently, and do not introduce synonyms.
6. Write default values and special values exactly, e.g. "`0` is treated as `60`", never "a sensible default is used".
7. Use consistent Markdown:
   - One `#` heading for the title, and numbered `##` to `#####` headings for sections, with the number followed by a period, e.g. `#### 5.4.3. Behaviour`.
   - Do not hard-wrap paragraphs.
   - Use fenced code blocks with a language identifier.
8. Section numbers may change when sections are inserted. Cross-references use Markdown links to section anchors, and the author updates links broken by renumbering in the same change.

### 6. Change process

1. A change that alters observable behaviour MUST update the specification in the same pull request, and add an entry to the changes section. This restates the existing rule in the [library development process](library-development-process.md) that code and specification stay in sync.
2. When the implementation and the specification disagree, the owners decide which one is correct. If the implementation is wrong, a `Type/Bug` issue is created. If the specification is wrong or silent, the specification is fixed, and if the fix changes documented behaviour, it goes through the proposal process.
3. Reviewers apply the following checklist to every specification change:
   - [ ] Every new or changed configuration field has a type, default and meaning, including special values.
   - [ ] Behaviour on failure, at boundaries and on exhaustion is specified.
   - [ ] Errors are specified with their types.
   - [ ] Interactions with existing features are specified.
   - [ ] No signatures or doc comments are copied from the source.
   - [ ] No tutorial content, recommendations or repeated examples are added.
   - [ ] Normative changes are listed in the changes section.

### 7. Migration

Existing specifications are migrated incrementally, starting with the HTTP library. Each migration is done section by section in pull requests that do not change library behaviour. Content removed from a specification is moved to its new home (section 1) in the same pull request, or linked in the pull request description when it already exists there. Gaps found during migration are fixed in the specification when the implementation behaviour is intended, and reported as `Type/Bug` issues when it is not.

The migration of the HTTP library specification ([module-ballerina-http#2768](https://github.com/ballerina-platform/module-ballerina-http/pull/2768)) applies this guide, and can be used as a reference.

## Alternatives

- **Keep the current hybrid format.** Rejected. The specification cannot serve as the contract while behaviour is described only by example, and the motivation shows the cost to users.
- **Split each specification into `spec.md` and `guide.md`.** Rejected. A per-library guide duplicates `README.md`/`Module.md`, BBEs and ballerina.io content, and adds another document that drifts without a clear owner or rendering location.
- **Generate the specification from API Docs.** Rejected. API Docs describe individual symbols, and cannot express cross-cutting behaviour such as routing precedence, the order in which client features apply, or error mapping.

## Risks and Assumptions

- Migrating large specifications takes effort. Incremental, behaviour-preserving pull requests and starting with the most-used library keep the cost bounded.
- Writing precise rules exposes behaviour that is accidental or buggy. This is intended. Such behaviour is reported as a bug rather than enshrined in the specification.

## Future Work

- **Conformance traceability**: Linking test cases to the specification sections they verify, so that coverage of the specification can be measured.
- **Linting**: Checking the structure, heading numbering and the presence of the changes section in CI.
- **Template repository update**: Adding a specification skeleton that follows this guide to the library repository template.
