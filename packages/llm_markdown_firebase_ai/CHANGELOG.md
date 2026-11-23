## 0.1.2

* An animation and a screenshot of a reply with thinking, a search call and
  sources.

## 0.1.1

* A reply stopped before the first response arrives cancels the request
  quietly instead of ending with an error.
* Every blocking finish reason (blocklist, prohibited content, personal
  data, malformed function call and others) ends the reply with an error;
  only safety and recitation did.

## 0.1.0

* `addFirebaseAIStream` reads `firebase_ai` replies into a
  `StreamingMarkdownController`: text, thought summaries, function calls,
  Google Search sources, blocked replies as errors, and stop support.
