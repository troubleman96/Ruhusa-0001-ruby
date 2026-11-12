module RMG
  # Central place for deciding which operations need human review.
  class Policy
    def decision(action:, importance: 5)
      return :deny unless %w[create update delete].include?(action)

      # Destructive or high-impact operations always require a human.
      return :human if %w[update delete].include?(action)
      return :human if importance.to_i >= 8

      # Low-impact new memories can be stored automatically.
      :allow
    end
  end
end
