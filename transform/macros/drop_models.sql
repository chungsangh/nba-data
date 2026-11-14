{#-
    Drop the tables of the named models so the next run rebuilds them from scratch.

        dbt run-operation drop_models --args '{model_names: [fct_shots]}'

    Used by scripts/reset_changed_incrementals.sh before a prod run, for incremental models whose
    definition changed since the last prod run (an incremental run would fail on a schema change,
    or leave history computed with the old logic).
-#}
{% macro drop_models(model_names) %}
    {% if not execute %}{{ return(none) }}{% endif %}
    {% for node in graph.nodes.values()
        if node.resource_type == 'model' and node.name in model_names %}
        {% set relation = adapter.get_relation(
            database=node.database, schema=node.schema, identifier=node.alias
        ) %}
        {% if relation is not none %}
            {% do adapter.drop_relation(relation) %}
            {% do log("Dropped " ~ relation ~ " (" ~ node.name ~ ") for a full rebuild", info=true) %}
        {% else %}
            {% do log("Nothing to drop for " ~ node.name ~ ": it does not exist yet", info=true) %}
        {% endif %}
    {% endfor %}
    {% do adapter.commit() %}
{% endmacro %}
