"""Exercise owned DocC curation, overload links and nonwriting drift detection."""

import copy
import tempfile
import unittest
from pathlib import Path

import curate_docc


def symbol(name, kind="swift.struct", identifier=None, module="Example", source="Values.swift", **extra):
    """Build the smallest realistic public declaration graph fixture."""
    components = name.split("/")
    result = {"identifier": {"precise": identifier or f"s:{len(module)}{module}:{name}"},
              "kind": {"identifier": kind}, "pathComponents": components,
              "accessLevel": "public", "location": {"uri": f"file:///project/Sources/{module}/{source}"},
              "docComment": {"lines": [{"text": f"Existing {name} contract."}]}}
    result.update(extra)
    return result


def graph(symbols, relationships=(), module="Example"):
    """Associate fixture declarations and relationships with an explicit module."""
    return {"module": {"name": module}, "symbols": symbols, "relationships": list(relationships)}


def member(child, parent, kind="memberOf"):
    """Create membership by identity rather than assuming a spelling prefix."""
    return {"source": child["identifier"]["precise"], "target": parent["identifier"]["precise"], "kind": kind}


class ReferenceCurationTests(unittest.TestCase):
    """Keep all authored navigation complete without claiming foreign API ownership."""

    def test_stable_hash_matches_installed_docc_overload_identifiers(self):
        """Published DocC paths use folded FNV-1, not Python's randomized hash."""
        self.assertEqual(curate_docc.stable_symbol_hash(
            "s:11DiscordCore9JSONValueO5parse_6limitsAC10Foundation4DataV_AA10JSONLimitsVtKFZ"), "2d5ua")
        self.assertEqual(curate_docc.stable_symbol_hash(
            "s:15DiscordCommands21CommandOptionsBuilderO15buildExpressionySay0A6Models011ApplicationC12OptionCreateVGAGFZ"),
                         "8y0bn")
        self.assertEqual(curate_docc.stable_symbol_hash(""), "146ys")

    def test_nested_types_members_and_associated_types_follow_relationships(self):
        """The index links only parents; every nested type receives its own page."""
        parent = symbol("Container", "swift.protocol")
        nested = symbol("Container/State", "swift.enum")
        case = symbol("Container/State/ready", "swift.enum.case")
        associated = symbol("Container/Element", "swift.associatedtype")
        method = symbol("Container/read()", "swift.method")
        declarations = [parent, nested, case, associated, method]
        original = copy.deepcopy(declarations)
        files, stats = curate_docc.reference_files("Example", [graph(declarations, [member(nested, parent),
            member(case, nested), member(associated, parent, "requirementOf"), member(method, parent, "requirementOf")])])
        self.assertEqual(stats["typePages"], 2)
        self.assertEqual(stats["memberLinks"], 4)
        self.assertIn("### Nested enumerations\n\n- ``Example/Container/State``", files[Path("Reference/Container.md")])
        self.assertIn("### Associated types", files[Path("Reference/Container.md")])
        self.assertIn("### Cases\n\n- ``Example/Container/State/ready``", files[Path("Reference/Container.State.md")])
        self.assertNotIn("Container/State", files[Path("APIReference.md")])
        self.assertNotIn("Existing Container contract", files[Path("Reference/Container.md")])
        self.assertEqual(declarations, original)

    def test_overloads_have_distinct_hashes_and_default_implementations_have_a_group(self):
        """Identical spellings never produce ambiguous member links."""
        parent = symbol("Readable", "swift.protocol")
        requirement = symbol("Readable/read()", "swift.method", identifier="s:7Example:requirement")
        default = symbol("Readable/read()", "swift.method", identifier="s:7Example:default")
        files, _ = curate_docc.reference_files("Example", [graph([parent, default, requirement], [
            member(requirement, parent, "requirementOf"),
            member(default, requirement, "defaultImplementationOf")])])
        page = files[Path("Reference/Readable.md")]
        for declaration in [requirement, default]:
            self.assertIn("Example/Readable/read()-" + curate_docc.stable_symbol_hash(declaration["identifier"]["precise"]), page)
        self.assertIn("### Default implementations", page)
        self.assertIn("### Instance methods", page)

    def test_inherited_symbols_are_not_curated_but_remain_part_of_collision_resolution(self):
        """An inherited overload still requires a precise link for the owned member."""
        parent = symbol("Value")
        own = symbol("Value/init(from:)", "swift.init")
        inherited = symbol("Value/init(from:)", "swift.init", identifier="s:Swift:init::SYNTHESIZED::Value")
        foreign = symbol("Foreign", module="Dependency")
        private = symbol("Private", accessLevel="private")
        files, stats = curate_docc.reference_files("Example", [graph([parent, own, inherited, foreign, private], [
            member(own, parent), member(inherited, parent)])])
        self.assertEqual(stats["typePages"], 1)
        self.assertEqual(stats["memberLinks"], 1)
        self.assertIn("init(from:)-" + curate_docc.stable_symbol_hash(own["identifier"]["precise"]),
                      files[Path("Reference/Value.md")])

    def test_external_extensions_curate_owned_functions_without_foreign_type_pages(self):
        """The Swift namespace is required for resolving standard-library extensions."""
        foreign = symbol("KeyedContainer", "swift.extension", swiftExtension={"extendedModule": "Swift"})
        function = symbol("KeyedContainer/decodeField(_:)", "swift.method", identifier="s:SwiftContainer7ExampleEdecode",
                          swiftExtension={"extendedModule": "Swift"})
        files, stats = curate_docc.reference_files("Example", [graph([foreign, function], [member(function, foreign)])])
        self.assertEqual(stats["typePages"], 0)
        self.assertEqual(stats["externalExtensionLinks"], 1)
        self.assertEqual(set(files), {Path("APIReference.md")})
        self.assertIn("``Example/Swift``", files[Path("APIReference.md")])
        self.assertIn("``Example/Swift/KeyedContainer``", files[Path("APIReference.md")])
        self.assertIn("``Example/Swift/KeyedContainer/decodeField(_:)``", files[Path("APIReference.md")])

    def test_graph_and_relationship_order_do_not_change_output(self):
        """Fresh compiler enumeration order cannot cause committed documentation churn."""
        parent = symbol("Parent")
        a, b = symbol("Parent/a", "swift.property"), symbol("Parent/b", "swift.property")
        relations = [member(a, parent), member(b, parent)]
        first = curate_docc.reference_files("Example", [graph([parent, a, b], relations)])
        second = curate_docc.reference_files("Example", [graph([b, a, parent], reversed(relations))])
        self.assertEqual(first, second)

    def test_large_model_catalog_groups_by_domain_instead_of_one_structure_list(self):
        """Model navigation joins related request and value files into useful domains."""
        declarations = [symbol(f"Message{index}", module="DiscordModels", source="MessageRequest.swift") for index in range(26)]
        declarations.extend([symbol("User", module="DiscordModels", source="User.swift"),
                             symbol("Lobby", module="DiscordModels", source="Lobby.swift")])
        files, _ = curate_docc.reference_files("DiscordModels", [graph(declarations, module="DiscordModels")])
        index = files[Path("APIReference.md")]
        self.assertIn("### Messages, polls and components", index)
        self.assertIn("### Users and connections", index)
        self.assertIn("### Lobbies and identity profiles", index)
        self.assertEqual(curate_docc.readable_name("HTTPResources.generated"), "HTTP Resources")

    def test_check_does_not_write_and_write_removes_only_generated_stale_pages(self):
        """Drift is detected before mutation and unrelated guides survive refreshes."""
        files, _ = curate_docc.reference_files("Example", [graph([symbol("Value")])])
        with tempfile.TemporaryDirectory() as temporary:
            catalog = Path(temporary) / "Example.docc"
            self.assertEqual(len(curate_docc.synchronize(catalog, files)), 2)
            self.assertFalse(catalog.exists())
            curate_docc.synchronize(catalog, files, write=True)
            self.assertEqual(curate_docc.synchronize(catalog, files), [])
            guide = catalog / "Guide.md"
            guide.write_text("Authored guide")
            stale = catalog / "Reference/Stale.md"
            stale.write_text(curate_docc.GENERATED + "\n# Stale\n")
            self.assertEqual(curate_docc.synchronize(catalog, files), ["Reference/Stale.md"])
            self.assertTrue(stale.exists())
            curate_docc.synchronize(catalog, files, write=True)
            self.assertFalse(stale.exists())
            self.assertEqual(guide.read_text(), "Authored guide")

    def test_write_refuses_authored_reference_content(self):
        """An unexpected authored file is never silently overwritten or deleted."""
        files, _ = curate_docc.reference_files("Example", [graph([symbol("Value")])])
        with tempfile.TemporaryDirectory() as temporary:
            catalog = Path(temporary)
            path = catalog / "APIReference.md"
            path.write_text("Authored reference")
            with self.assertRaisesRegex(ValueError, "overwrite authored"):
                curate_docc.synchronize(catalog, files, write=True)
            self.assertEqual(path.read_text(), "Authored reference")
            path.unlink()
            curate_docc.synchronize(catalog, files, write=True)
            stale = catalog / "Reference/Manual.md"
            stale.write_text("Authored page")
            with self.assertRaisesRegex(ValueError, "remove authored"):
                curate_docc.synchronize(catalog, files, write=True)
            self.assertEqual(stale.read_text(), "Authored page")

    def test_invalid_graphs_fail_instead_of_dropping_owned_declarations(self):
        """Wrong modules, missing nesting and conflicting identities cannot pass a check."""
        for invalid in [graph([symbol("Value")], module="Other"), graph([symbol("Missing/Child")])]:
            with self.assertRaises(ValueError):
                curate_docc.reference_files("Example", [invalid])
        original = symbol("Value")
        changed = copy.deepcopy(original)
        changed["pathComponents"] = ["Changed"]
        with self.assertRaisesRegex(ValueError, "Conflicting"):
            curate_docc.reference_files("Example", [graph([original, changed])])

    def test_location_ownership_is_not_guessed_from_a_module_name_substring(self):
        """Absolute source components and exact mangled module lengths define ownership."""
        own = symbol("Value", module="Example")
        self.assertTrue(curate_docc.owned_symbol(own, "Example"))
        foreign = symbol("Value", module="ExampleTests")
        self.assertFalse(curate_docc.owned_symbol(foreign, "Example"))
        own.pop("location")
        self.assertTrue(curate_docc.owned_symbol(own, "Example"))
        foreign.pop("location")
        self.assertFalse(curate_docc.owned_symbol(foreign, "Example"))


if __name__ == "__main__":
    unittest.main()
