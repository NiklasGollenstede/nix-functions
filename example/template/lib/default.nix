dirname: inputs: inputs.functions.lib.importLib inputs dirname { rename = {
    functions = "fun"; # use `inputs.functions.lib` as ((`inputs.`)`self.`)`lib.__internal__.fun` (default would be `lib.__internal__.functions`)
    self = "my"; # use the functions defined in this directory as ((`inputs.`)`self.`)`lib.__internal__.my` (default would be `lib.__internal__.self`)
}; }
