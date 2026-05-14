describe('reference.context (harness sanity)', function()
  it('runs a placeholder test to verify plenary.busted is wired up', function()
    -- Arrange
    local expected = true

    -- Act
    local actual = true

    -- Assert
    assert.is_true(actual)
    assert.are.equal(expected, actual)
  end)
end)
