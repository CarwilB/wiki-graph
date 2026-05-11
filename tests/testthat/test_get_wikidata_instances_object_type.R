library(testthat)
library(dplyr)
library(purrr)
library(tibble)

# Load the source file with functions to test
# (Assumes this test file is in tests/testthat/)
source("../../get_wikidata_instances.R")

# ============================================================================
# HELPER FUNCTION TESTS
# ============================================================================

test_that(".build_sparql_query builds correct P31 query", {
  query <- .build_sparql_query("Q5", country = NULL, property_id = "P31", limit = 100)
  expect_true(grepl("wdt:P31 wd:Q5", query))
  expect_true(grepl("LIMIT 100", query))
  expect_false(grepl("wdt:P17", query))  # No country filter
})

test_that(".build_sparql_query builds correct P279 query", {
  query <- .build_sparql_query("Q5", country = NULL, property_id = "P279", limit = 100)
  expect_true(grepl("wdt:P279 wd:Q5", query))
  expect_true(grepl("LIMIT 100", query))
})

test_that(".build_sparql_query includes country filter when provided", {
  query <- .build_sparql_query("Q1062710", country = "Q750", property_id = "P31", limit = 500)
  expect_true(grepl("wdt:P31 wd:Q1062710", query))
  expect_true(grepl("wdt:P17 wd:Q750", query))
  expect_true(grepl("LIMIT 500", query))
})

test_that(".build_sparql_query rejects invalid property_id", {
  expect_error(.build_sparql_query("Q5", property_id = "P999"),
               "property_id must be 'P31' or 'P279'")
})

test_that(".extract_instance_or_subclass returns character(0) for entity without claims", {
  entity <- list()
  result <- .extract_instance_or_subclass(entity, "P31")
  expect_equal(result, character(0))
})

test_that(".extract_instance_or_subclass returns character(0) for missing property", {
  entity <- list(claims = list(P300 = data.frame()))
  result <- .extract_instance_or_subclass(entity, "P31")
  expect_equal(result, character(0))
})

test_that(".extract_instance_or_subclass extracts P31 QIDs correctly", {
  # Mock entity structure with P31 claims
  entity <- list(
    claims = list(
      P31 = structure(
        list(
          mainsnak = structure(
            list(
              datavalue = list(
                list(id = "Q5"),
                list(id = "Q15989994")
              )
            ),
            class = "data.frame",
            row.names = c(1, 2)
          )
        ),
        class = "data.frame",
        row.names = c(1, 2)
      )
    )
  )
  result <- .extract_instance_or_subclass(entity, "P31")
  expect_equal(result, c("Q5", "Q15989994"))
})

test_that(".extract_instance_or_subclass extracts P279 QIDs correctly", {
  entity <- list(
    claims = list(
      P279 = structure(
        list(
          mainsnak = structure(
            list(
              datavalue = list(
                list(id = "Q431289"),
                list(id = "Q5107519")
              )
            ),
            class = "data.frame",
            row.names = c(1, 2)
          )
        ),
        class = "data.frame",
        row.names = c(1, 2)
      )
    )
  )
  result <- .extract_instance_or_subclass(entity, "P279")
  expect_equal(result, c("Q431289", "Q5107519"))
})

# ============================================================================
# ENTITY PARSING TESTS
# ============================================================================

test_that(".parse_entity with object_type='instance' creates instance_of column", {
  entity <- list(
    labels = list(en = list(value = "Human")),
    descriptions = list(en = list(value = "A person")),
    claims = list(
      P31 = structure(
        list(
          mainsnak = structure(
            list(
              datavalue = list(list(id = "Q5"))
            ),
            class = "data.frame",
            row.names = 1
          )
        ),
        class = "data.frame",
        row.names = 1
      )
    ),
    sitelinks = NULL
  )

  result <- .parse_entity(entity, "Q5", NULL, NULL, "en", object_type = "instance")
  expect_true("instance_of" %in% names(result))
  expect_false("subclass_of" %in% names(result))
  expect_equal(result$instance_of, list("Q5"))
})

test_that(".parse_entity with object_type='subclass' creates subclass_of column", {
  entity <- list(
    labels = list(en = list(value = "Mammal")),
    descriptions = list(en = list(value = "A warm-blooded vertebrate")),
    claims = list(
      P279 = structure(
        list(
          mainsnak = structure(
            list(
              datavalue = list(list(id = "Q7661"))
            ),
            class = "data.frame",
            row.names = 1
          )
        ),
        class = "data.frame",
        row.names = 1
      )
    ),
    sitelinks = NULL
  )

  result <- .parse_entity(entity, "Q7661", NULL, NULL, "en", object_type = "subclass")
  expect_true("subclass_of" %in% names(result))
  expect_false("instance_of" %in% names(result))
  expect_equal(result$subclass_of, list("Q7661"))
})

test_that(".parse_entity extracts labels in multiple languages", {
  entity <- list(
    labels = list(en = list(value = "France"), es = list(value = "Francia")),
    descriptions = list(en = list(value = "Country"), es = list(value = "País")),
    claims = list(),
    sitelinks = NULL
  )

  result <- .parse_entity(entity, "Q142", NULL, NULL, c("en", "es"), object_type = "instance")
  expect_equal(result$label_en, "France")
  expect_equal(result$label_es, "Francia")
  expect_equal(result$description_en, "Country")
  expect_equal(result$description_es, "País")
})

test_that(".parse_entity handles entity without sitelinks", {
  entity <- list(
    labels = list(en = list(value = "Test")),
    descriptions = list(en = list(value = "Test entity")),
    claims = list(),
    sitelinks = NULL
  )

  result <- .parse_entity(entity, "Q999", NULL, NULL, "en", object_type = "instance")
  expect_equal(result$wikipedia_articles, list(character(0)))
})

test_that(".parse_entity handles entity with empty claims", {
  entity <- list(
    labels = list(en = list(value = "Test")),
    descriptions = list(en = list(value = "Test")),
    claims = list(),
    sitelinks = NULL
  )

  result <- .parse_entity(entity, "Q999", NULL, NULL, "en", object_type = "instance")
  expect_equal(result$instance_of, list(character(0)))
})

# ============================================================================
# PUBLIC FUNCTION PARAMETER TESTS
# ============================================================================

test_that("get_wikidata_instances accepts object_type='instance'", {
  expect_no_error(
    {
      # Mock internal functions to avoid actual API calls
      mockery::stub(get_wikidata_instances, ".sparql_get_qids", function(...) character(0))
      get_wikidata_instances("Q5", object_type = "instance")
    }
  )
})

test_that("get_wikidata_instances accepts object_type='subclass'", {
  expect_no_error(
    {
      mockery::stub(get_wikidata_instances, ".sparql_get_qids", function(...) character(0))
      get_wikidata_instances("Q5", object_type = "subclass")
    }
  )
})

test_that("get_wikidata_instances rejects invalid object_type", {
  expect_error(
    get_wikidata_instances("Q5", object_type = "invalid"),
    'object_type must be "instance" or "subclass"'
  )
})

test_that("resume_get_wikidata_instances accepts object_type='instance'", {
  partial_df <- tibble(qid = "Q1", label_en = "Test")
  expect_no_error(
    {
      mockery::stub(resume_get_wikidata_instances, ".sparql_get_qids", function(...) "Q1")
      resume_get_wikidata_instances(partial_df, "Q5", object_type = "instance")
    }
  )
})

test_that("resume_get_wikidata_instances accepts object_type='subclass'", {
  partial_df <- tibble(qid = "Q1", label_en = "Test")
  expect_no_error(
    {
      mockery::stub(resume_get_wikidata_instances, ".sparql_get_qids", function(...) "Q1")
      resume_get_wikidata_instances(partial_df, "Q5", object_type = "subclass")
    }
  )
})

test_that("resume_get_wikidata_instances rejects invalid object_type", {
  partial_df <- tibble(qid = "Q1")
  expect_error(
    resume_get_wikidata_instances(partial_df, "Q5", object_type = "invalid"),
    'object_type must be "instance" or "subclass"'
  )
})

# ============================================================================
# BACKWARD COMPATIBILITY TESTS
# ============================================================================

test_that("get_wikidata_instances defaults to object_type='instance'", {
  # Should not raise an error about missing object_type
  expect_no_error(
    {
      mockery::stub(get_wikidata_instances, ".sparql_get_qids", function(...) character(0))
      get_wikidata_instances("Q5")
    }
  )
})

test_that("resume_get_wikidata_instances defaults to object_type='instance'", {
  partial_df <- tibble(qid = "Q1")
  expect_no_error(
    {
      mockery::stub(resume_get_wikidata_instances, ".sparql_get_qids", function(...) "Q1")
      resume_get_wikidata_instances(partial_df, "Q5")
    }
  )
})

test_that(".parse_entity defaults to object_type='instance'", {
  entity <- list(
    labels = list(en = list(value = "Test")),
    descriptions = list(en = list(value = "Test")),
    claims = list(),
    sitelinks = NULL
  )

  # Call without explicit object_type
  result <- .parse_entity(entity, "Q999", NULL, NULL, "en")
  # Should have instance_of, not subclass_of
  expect_true("instance_of" %in% names(result))
  expect_false("subclass_of" %in% names(result))
})

# ============================================================================
# EDGE CASE TESTS
# ============================================================================

test_that(".parse_entity handles entity with both labels and no labels", {
  entity_with_labels <- list(
    labels = list(en = list(value = "Test")),
    descriptions = list(en = list(value = "Test")),
    claims = list(),
    sitelinks = NULL
  )
  entity_no_labels <- list(
    labels = list(),
    descriptions = list(),
    claims = list(),
    sitelinks = NULL
  )

  result1 <- .parse_entity(entity_with_labels, "Q1", NULL, NULL, "en", object_type = "instance")
  result2 <- .parse_entity(entity_no_labels, "Q2", NULL, NULL, "en", object_type = "instance")

  expect_equal(result1$label_en, "Test")
  expect_true(is.na(result2$label_en))
})

test_that(".extract_instance_or_subclass handles empty claims correctly", {
  entity_with_empty_p31 <- list(
    claims = list(
      P31 = structure(
        list(mainsnak = structure(list(), class = "data.frame", row.names = integer(0))),
        class = "data.frame",
        row.names = integer(0)
      )
    )
  )

  result <- .extract_instance_or_subclass(entity_with_empty_p31, "P31")
  expect_equal(result, character(0))
})

test_that(".build_sparql_query limit parameter is respected", {
  query1 <- .build_sparql_query("Q5", limit = 50, property_id = "P31")
  query2 <- .build_sparql_query("Q5", limit = 10000, property_id = "P31")

  expect_true(grepl("LIMIT 50", query1))
  expect_true(grepl("LIMIT 10000", query2))
})

# ============================================================================
# INTEGRATION TESTS
# ============================================================================

test_that("object_type parameter flows through function call chain", {
  # This tests that the parameter correctly threads through to lower-level functions
  entity <- list(
    labels = list(en = list(value = "Organism")),
    descriptions = list(en = list(value = "Living thing")),
    claims = list(
      P279 = structure(
        list(
          mainsnak = structure(
            list(datavalue = list(list(id = "Q11042"))),
            class = "data.frame",
            row.names = 1
          )
        ),
        class = "data.frame",
        row.names = 1
      )
    ),
    sitelinks = NULL
  )

  # Test with object_type = "subclass"
  result_subclass <- .parse_entity(entity, "Q2471052", NULL, NULL, "en",
                                   object_type = "subclass")

  # Should have subclass_of column, not instance_of
  expect_true("subclass_of" %in% names(result_subclass))
  expect_false("instance_of" %in% names(result_subclass))
  expect_equal(result_subclass$subclass_of, list("Q11042"))
})

# ============================================================================
# COLUMN NAMING TESTS
# ============================================================================

test_that("instance_of column is created when object_type='instance'", {
  entity <- list(
    labels = list(en = list(value = "Homo sapiens")),
    descriptions = list(en = list(value = "Species")),
    claims = list(
      P31 = structure(
        list(
          mainsnak = structure(
            list(datavalue = list(list(id = "Q7725634"))),
            class = "data.frame",
            row.names = 1
          )
        ),
        class = "data.frame",
        row.names = 1
      )
    ),
    sitelinks = NULL
  )

  result <- .parse_entity(entity, "Q15978631", NULL, NULL, "en", object_type = "instance")
  expect_true("instance_of" %in% names(result))
})

test_that("subclass_of column is created when object_type='subclass'", {
  entity <- list(
    labels = list(en = list(value = "Canis")),
    descriptions = list(en = list(value = "Genus of canines")),
    claims = list(
      P279 = structure(
        list(
          mainsnak = structure(
            list(datavalue = list(list(id = "Q7711"))),
            class = "data.frame",
            row.names = 1
          )
        ),
        class = "data.frame",
        row.names = 1
      )
    ),
    sitelinks = NULL
  )

  result <- .parse_entity(entity, "Q865", NULL, NULL, "en", object_type = "subclass")
  expect_true("subclass_of" %in% names(result))
})
