def capabilities:
  (.supported_parameters // null) as $params
  | {
      tool_calling: (
        ($params | type == "array")
        and ($params | contains(["tool_choice"]))
        and ($params | contains(["tools"]))
      ),
      structured_outputs: (
        ($params | type == "array")
        and ($params | contains(["structured_outputs"]))
      ),
      reasoning: (
        ($params | type == "array")
        and (
          ($params | contains(["reasoning"]))
          or ($params | contains(["include_reasoning"]))
        )
      ),
      response_format: (
        ($params | type == "array")
        and ($params | contains(["response_format"]))
      ),
      web_search: (
        ($params | type == "array")
        and ($params | contains(["web_search_options"]))
      )
    };
