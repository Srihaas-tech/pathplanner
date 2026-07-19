/// Path-model-neutral registry of named commands used by the open project.
///
/// Event names are collected while autos (and legacy paths) are loaded. Keeping
/// the registry outside of either project page lets the legacy and Path2 editor
/// stacks share the command widgets without depending on one another.
class ProjectEventRegistry {
  ProjectEventRegistry._();

  static final Set<String> events = <String>{};

  static void clear() => events.clear();
}
