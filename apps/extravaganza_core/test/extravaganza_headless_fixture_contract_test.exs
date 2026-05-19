defmodule Extravaganza.HeadlessFixtureContractTest do
  use ExUnit.Case, async: true

  alias Extravaganza.{Config, ProductPack}
  alias Extravaganza.HeadlessFixtures.LinearSource

  test "Linear headless subject defaults preserve the product source shape" do
    subject = LinearSource.start_subject(%{issue_id: "ENG-101"})

    assert subject == %{
             external_ref: "linear:ENG-101",
             title: "Headless deterministic start ENG-101",
             description: "Admitted by the headless product command path.",
             source_kind: Config.load().linear_source_kind,
             payload: %{
               "issue_id" => "ENG-101",
               "identifier" => "ENG-101",
               "title" => "Headless deterministic start ENG-101",
               "description" => "Admitted by the headless product command path.",
               "state" => "Todo"
             },
             normalized_payload: %{
               "issue_id" => "ENG-101",
               "identifier" => "ENG-101",
               "title" => "Headless deterministic start ENG-101",
               "description" => "Admitted by the headless product command path.",
               "state" => "Todo",
               "labels" => ["headless", "deterministic"]
             }
           }
  end

  test "Linear source-sync defaults preserve the product source page item shape" do
    issue = LinearSource.source_issue(%{issue_id: "ENG-202", now: "2026-05-18T12:00:00Z"})

    assert issue == %{
             id: "ENG-202",
             identifier: "ENG-202",
             title: "Headless deterministic source ENG-202",
             description: "Admitted by the headless source command path.",
             state: %{name: "Todo", type: "unstarted"},
             labels: ["headless", "deterministic"],
             url: "https://linear.app/example/issue/ENG-202",
             updated_at: "2026-05-18T12:00:00Z"
           }
  end

  test "headless fixture defaults are tied to the product pack workflow role refs" do
    assert LinearSource.contract() == %{
             source_kind: Config.load().linear_source_kind,
             workflow_role_refs: ProductPack.workflow_role_refs()
           }

    assert ProductPack.workflow_role_refs() == %{
             source_role_ref: :issue_tracker,
             runtime_role_ref: :coding_agent_runtime,
             publication_role_ref: :source_publication,
             evidence_role_refs: [:proposed_change_evidence],
             resource_effect_role_refs: [:proposed_change_cleanup],
             tool_role_refs: [:issue_graphql_tool]
           }
  end
end
