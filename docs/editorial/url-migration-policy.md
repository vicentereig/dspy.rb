# URL migration policy

`url-redirects.yml` is the source of truth for documentation moves. Every
corpus redirect starts as `planned`. It becomes `active` only after its unique
content and semantic anchors have reached their declared destinations, inbound
fragments are dispositioned, and the old source no longer owns the route.
Planned pages remain published and generate no redirect artifact. For active
entries, Bridgetown emits one `index.html` at the old route and includes the
resolved mapping in public `/redirects.json`.

- Site routes are lowercase and end in `/`. GitHub Pages serves the directory
  index for slashless requests; mixed-case requests are invalid and may 404.
- Internal redirect targets acquire the configured `/dspy.rb` base path.
  External targets remain unchanged.
- Redirect pages use a canonical link to the final target, a meta refresh for
  clients without JavaScript, and `location.replace` for fragment handling.
- Every heading in an old source is explicitly mapped or retired with a reason.
  A mapping may replace an old fragment with a new fragment or route. A named
  retired fragment falls back to the entry's default target for the recorded
  reason. Other unknown fragments fall back to the reviewed default target;
  fragments are never blindly copied across a merge or external move.
- Targets must be final. A target may not also be a redirect source. When a
  page moves again, update every predecessor to the new destination in the
same change; chains and loops fail validation.
- Redirect JavaScript uses script-safe JSON and treats malformed percent
  encoding as an unknown fragment, which falls back to the default target.

Run `ruby scripts/validate_url_redirects.rb` from `docs/` to check the source
manifest. After a production build, add `--output output` to verify generated
artifacts, canonical metadata, base paths, and the public JSON manifest.
