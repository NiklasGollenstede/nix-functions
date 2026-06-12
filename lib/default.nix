dirname: inputs: (import "${dirname}/imports.nix" dirname inputs).importLib inputs dirname { rename = {
    self = "fun";
}; noSpread = [ "bash" ]; }
