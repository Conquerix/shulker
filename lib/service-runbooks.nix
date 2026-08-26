{ lib }:
{
  discovered,
  legacy,
  reservedPageNames,
}:

let
  inherit (builtins)
    attrNames
    deepSeq
    head
    length
    map
    ;
  inherit (lib)
    hasPrefix
    removePrefix
    replaceStrings
    sort
    unique
    ;

  fail = message: throw "Service runbooks: ${message}";
  require = condition: message: if condition then true else fail message;
  titleToFolder = title: lib.toLower (replaceStrings [ " " ] [ "-" ] title);
  titleToPageName = title: "Service-${replaceStrings [ " " ] [ "-" ] title}.md";
  validTitle = title: builtins.match "[A-Za-z0-9]+( [A-Za-z0-9]+)*" title != null;
  validFolder = folder: builtins.match "[a-z0-9]+(-[a-z0-9]+)*" folder != null;
  pageNames = pages: map (page: page.pageName) pages;

  normalizeDiscovered =
    record:
    let
      folder = record.folder;
      readmeType = record.readmeType;
      content = if readmeType == "regular" then record.content else "";
      lines = lib.splitString "\n" content;
      firstLine = if lines == [ ] then "" else head lines;
      title = removePrefix "# " firstLine;
      checks = [
        (require (validFolder folder) "invalid service folder '${folder}'")
        (require (readmeType == "regular") "${folder}/README.md must be a regular file")
        (require (content != "") "${folder}/README.md must be non-empty")
        (require (
          hasPrefix "# " firstLine && validTitle title
        ) "${folder}/README.md must begin exactly '# <title>'")
        (require (
          titleToFolder title == folder
        ) "${folder}/README.md title does not normalize to its folder")
      ];
    in
    deepSeq checks {
      inherit title;
      pageName = titleToPageName title;
      source = record.source;
    };

  normalizeLegacy =
    pageName: record:
    let
      title = record.title;
      checks = [
        (require (validTitle title) "legacy '${pageName}' has an invalid title")
        (require (pageName == titleToPageName title) "legacy '${pageName}' is not derived from its title")
      ];
    in
    deepSeq checks {
      inherit title pageName;
      source = record.source;
    };

  normalizedPages =
    map normalizeDiscovered discovered
    ++ map (pageName: normalizeLegacy pageName legacy.${pageName}) (attrNames legacy);
  sortedPages = sort (left: right: left.pageName < right.pageName) normalizedPages;
  names = pageNames sortedPages;
  caseFoldedNames = map lib.toLower names;
  reservedNames = reservedPageNames;
  caseFoldedReservedNames = map lib.toLower reservedNames;
  checks = [
    (require (
      length reservedNames == length (unique reservedNames)
    ) "duplicate reserved Wiki page name")
    (require (
      length caseFoldedReservedNames == length (unique caseFoldedReservedNames)
    ) "case-folded reserved Wiki page collision")
    (require (length names == length (unique names)) "duplicate service Wiki page name")
    (require (
      length caseFoldedNames == length (unique caseFoldedNames)
    ) "case-folded service Wiki page collision")
    (require (
      lib.intersectLists names reservedNames == [ ]
    ) "service Wiki page collides with a static page")
    (require (
      lib.intersectLists caseFoldedNames caseFoldedReservedNames == [ ]
    ) "service Wiki page case-folds to a static page")
    (require (lib.all (
      name: !(hasPrefix "host-" (lib.toLower name))
    ) names) "service Wiki page uses reserved Host-* name")
    (require (lib.all (
      name: builtins.match "Service-[A-Za-z0-9]+(-[A-Za-z0-9]+)*\\.md" name != null
    ) names) "service Wiki page has an unsafe filename")
  ];
in
deepSeq checks sortedPages
