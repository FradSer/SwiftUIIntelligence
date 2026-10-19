/// Synthetic source data for live generation. These requests contain no document JSON or layouts.
public enum ExampleRequests {
  public static let equipment = """
  Compare these supplied hiking packs. Cedar costs 120 USD and weighs 900 g. Moss costs 85 USD and weighs 1200 g.
  Generate an editable comparison with a maximum price of 130 USD and maximum weight of 1300 g.
  Show price and weight comparisons and charts. Let me change conditions and select each product.
  Keep the filtered results and selection consistent. Use registered compare-records with products, measurements, and conditions records.
  Preserve price in USD and weight in grams. Do not invent products or measurements.
  """

  public static let meal = """
  Plan a meal from this synthetic recipe for 2 people: lentils 200 g, rice 150 g, carrots 100 g.
  The supplied sequential steps are preparation for 10 minutes, cooking for 25 minutes, and serving for 5 minutes.
  The original recipe serves 2 people. The requested plan serves 3 people. These are distinct inputs, not one shared count.
  Keep the original count fixed. Allow changes to the requested people count and meal time 2026-10-15T19:00:00Z.
  Show a shopping list and timeline that update together. Keep original recipe quantities as the scale basis.
  Use registered meal-plan with the supplied ingredients and ordered steps. Do not access a calendar or invent ingredients.
  """

  public static let bill = """
  Split this synthetic bill in one currency using integer minor units. Participants are Ada, Bo, and Cy.
  Soup costs 1001 minor units and Ada and Bo share it (Cy is excluded). Tea costs 502 minor units and Bo and Cy share it (Ada is excluded).
  The fixed service fee is 151 minor units. Show editable item amounts, participation toggles for each item/person pair, and service fee.
  Show personal food, service fee, item shares, and the exact payable total. Updates must happen locally after edits.
  Use registered split-bill. Retain a complete assignment matrix including excluded participants.
  Never label minor units as major currency amounts. Do not invent people or charges.
  """
}
