"""Small fallback for ``sphinx-tabs`` directives used by the Chinese manual.

The production docs dependency is ``sphinx-tabs``.  Some checked-in demo
workspaces still carry an older Sphinx environment without that package, so the
manual keeps building by rendering tabs as ordinary titled containers.  When the
real extension is installed, ``conf.py`` selects it and this module is unused.
"""

from docutils import nodes
from docutils.parsers.rst import directives
from sphinx.util.docutils import SphinxDirective


class TabsDirective(SphinxDirective):
    has_content = True

    def run(self):
        container = nodes.container(classes=["eh2-tabs-fallback"])
        self.state.nested_parse(self.content, self.content_offset, container)
        return [container]


class TabDirective(SphinxDirective):
    has_content = True
    required_arguments = 1
    optional_arguments = 10
    final_argument_whitespace = True
    option_spec = {
        "sync": str,
    }

    def run(self):
        title = " ".join(self.arguments)
        container = nodes.container(classes=["eh2-tab-fallback"])
        container += nodes.rubric(text=title)
        self.state.nested_parse(self.content, self.content_offset, container)
        return [container]


class GroupTabDirective(TabDirective):
    pass


class CodeTabDirective(SphinxDirective):
    has_content = True
    required_arguments = 2
    optional_arguments = 10
    final_argument_whitespace = True
    option_spec = {
        "caption": str,
        "linenos": directives.flag,
        "emphasize-lines": str,
    }

    def run(self):
        lang = self.arguments[0]
        title = " ".join(self.arguments[1:])
        container = nodes.container(classes=["eh2-tab-fallback", "eh2-code-tab-fallback"])
        container += nodes.rubric(text=title)
        literal = nodes.literal_block("\n".join(self.content), "\n".join(self.content))
        literal["language"] = lang
        if "caption" in self.options:
            container += nodes.caption(text=self.options["caption"])
        container += literal
        return [container]


def setup(app):
    app.add_directive("tabs", TabsDirective)
    app.add_directive("tab", TabDirective)
    app.add_directive("group-tab", GroupTabDirective)
    app.add_directive("code-tab", CodeTabDirective)
    return {
        "version": "1.0",
        "parallel_read_safe": True,
        "parallel_write_safe": True,
    }
