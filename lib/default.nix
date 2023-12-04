dirname: inputs: (import "${dirname}/imports.nix" dirname inputs).importLib inputs dirname { noSpread = [ "bash" ]; }
