{ lib }:

let
  escapeCell = value: lib.replaceStrings [ "|" "\n" ] [ "\\|" "<br>" ] (toString value);
  code = value: "`${escapeCell value}`";
  orNone = values: if values == [ ] then "_None._" else lib.concatStringsSep ", " values;

  collectEnabled =
    path: value:
    if builtins.isAttrs value && value ? enable && builtins.isBool value.enable then
      lib.optionals value.enable [ (lib.concatStringsSep "." path) ]
    else if builtins.isAttrs value then
      lib.concatLists (lib.mapAttrsToList (name: child: collectEnabled (path ++ [ name ]) child) value)
    else
      [ ];
in
{
  inherit code collectEnabled orNone;
  yesNo = value: if value then "yes" else "no";
  codeList = values: orNone (map code values);
  markdownTable =
    headers: rows:
    let
      renderRow = row: "| ${lib.concatStringsSep " | " (map escapeCell row)} |\n";
    in
    renderRow headers + renderRow (map (_: "---") headers) + lib.concatMapStringsSep "" renderRow rows;
}
