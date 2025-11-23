#[cfg(test)]
mod tests {
    use super::super::*;

    #[test]
    fn test_predicate_equality() {
        let p1 = Predicate {
            name: "is_a".to_string(),
            args: vec![
                Term::Constant("dog".to_string()),
                Term::Constant("animal".to_string()),
            ],
        };

        let p2 = Predicate {
            name: "is_a".to_string(),
            args: vec![
                Term::Constant("dog".to_string()),
                Term::Constant("animal".to_string()),
            ],
        };

        assert_eq!(p1, p2);
    }

    #[test]
    fn test_symbolic_add_fact() {
        let mut reasoner = SymbolicReasoner::new();

        let fact = Predicate {
            name: "is_a".to_string(),
            args: vec![
                Term::Constant("socrates".to_string()),
                Term::Constant("human".to_string()),
            ],
        };

        reasoner.add_fact(fact.clone());
        assert!(reasoner.facts.contains(&fact));
    }

    #[test]
    fn test_unification_constants() {
        let reasoner = SymbolicReasoner::new();

        let p1 = Predicate {
            name: "is_a".to_string(),
            args: vec![Term::Constant("dog".to_string())],
        };

        let p2 = Predicate {
            name: "is_a".to_string(),
            args: vec![Term::Constant("dog".to_string())],
        };

        let sub = reasoner.unify(&p1, &p2);
        assert!(sub.is_some());
        assert!(sub.unwrap().is_empty());
    }

    #[test]
    fn test_unification_variable() {
        let reasoner = SymbolicReasoner::new();

        let p1 = Predicate {
            name: "is_a".to_string(),
            args: vec![
                Term::Variable("X".to_string()),
                Term::Constant("human".to_string()),
            ],
        };

        let p2 = Predicate {
            name: "is_a".to_string(),
            args: vec![
                Term::Constant("socrates".to_string()),
                Term::Constant("human".to_string()),
            ],
        };

        let sub = reasoner.unify(&p1, &p2);
        assert!(sub.is_some());

        let sub = sub.unwrap();
        assert_eq!(sub.get("X"), Some(&Term::Constant("socrates".to_string())));
    }

    #[test]
    fn test_unification_fails_different_predicates() {
        let reasoner = SymbolicReasoner::new();

        let p1 = Predicate {
            name: "is_a".to_string(),
            args: vec![Term::Constant("dog".to_string())],
        };

        let p2 = Predicate {
            name: "likes".to_string(),
            args: vec![Term::Constant("dog".to_string())],
        };

        let sub = reasoner.unify(&p1, &p2);
        assert!(sub.is_none());
    }

    #[test]
    fn test_backward_chain_simple() {
        let mut reasoner = SymbolicReasoner::new();

        // Fact: is_a(socrates, human)
        reasoner.add_fact(Predicate {
            name: "is_a".to_string(),
            args: vec![
                Term::Constant("socrates".to_string()),
                Term::Constant("human".to_string()),
            ],
        });

        // Query: is_a(socrates, human)?
        let goal = Predicate {
            name: "is_a".to_string(),
            args: vec![
                Term::Constant("socrates".to_string()),
                Term::Constant("human".to_string()),
            ],
        };

        assert!(reasoner.backward_chain(&goal));
    }

    #[test]
    fn test_backward_chain_with_rule() {
        let mut reasoner = SymbolicReasoner::new();

        // Fact: is_a(socrates, human)
        reasoner.add_fact(Predicate {
            name: "is_a".to_string(),
            args: vec![
                Term::Constant("socrates".to_string()),
                Term::Constant("human".to_string()),
            ],
        });

        // Rule: is_a(X, human) → mortal(X)
        reasoner.add_rule(LogicRule {
            premises: vec![Predicate {
                name: "is_a".to_string(),
                args: vec![
                    Term::Variable("X".to_string()),
                    Term::Constant("human".to_string()),
                ],
            }],
            conclusion: Predicate {
                name: "mortal".to_string(),
                args: vec![Term::Variable("X".to_string())],
            },
            confidence: 1.0,
        });

        // Query: mortal(socrates)?
        let goal = Predicate {
            name: "mortal".to_string(),
            args: vec![Term::Constant("socrates".to_string())],
        };

        assert!(reasoner.backward_chain(&goal));
    }

    #[test]
    fn test_forward_chain_simple() {
        let mut reasoner = SymbolicReasoner::new();

        // Fact: is_a(socrates, human)
        reasoner.add_fact(Predicate {
            name: "is_a".to_string(),
            args: vec![
                Term::Constant("socrates".to_string()),
                Term::Constant("human".to_string()),
            ],
        });

        // Rule: is_a(X, human) → mortal(X)
        reasoner.add_rule(LogicRule {
            premises: vec![Predicate {
                name: "is_a".to_string(),
                args: vec![
                    Term::Variable("X".to_string()),
                    Term::Constant("human".to_string()),
                ],
            }],
            conclusion: Predicate {
                name: "mortal".to_string(),
                args: vec![Term::Variable("X".to_string())],
            },
            confidence: 1.0,
        });

        let derived = reasoner.forward_chain(10);

        assert!(!derived.is_empty());
        assert!(reasoner.facts.contains(&Predicate {
            name: "mortal".to_string(),
            args: vec![Term::Constant("socrates".to_string())],
        }));
    }

    #[test]
    fn test_forward_chain_multiple_rules() {
        let mut reasoner = SymbolicReasoner::new();

        // Facts
        reasoner.add_fact(Predicate {
            name: "is_a".to_string(),
            args: vec![
                Term::Constant("socrates".to_string()),
                Term::Constant("human".to_string()),
            ],
        });

        // Rule 1: is_a(X, human) → mortal(X)
        reasoner.add_rule(LogicRule {
            premises: vec![Predicate {
                name: "is_a".to_string(),
                args: vec![
                    Term::Variable("X".to_string()),
                    Term::Constant("human".to_string()),
                ],
            }],
            conclusion: Predicate {
                name: "mortal".to_string(),
                args: vec![Term::Variable("X".to_string())],
            },
            confidence: 1.0,
        });

        // Rule 2: mortal(X) → will_die(X)
        reasoner.add_rule(LogicRule {
            premises: vec![Predicate {
                name: "mortal".to_string(),
                args: vec![Term::Variable("X".to_string())],
            }],
            conclusion: Predicate {
                name: "will_die".to_string(),
                args: vec![Term::Variable("X".to_string())],
            },
            confidence: 1.0,
        });

        let derived = reasoner.forward_chain(10);

        // Should derive both mortal(socrates) and will_die(socrates)
        assert!(derived.len() >= 2);
        assert!(reasoner.facts.contains(&Predicate {
            name: "will_die".to_string(),
            args: vec![Term::Constant("socrates".to_string())],
        }));
    }

    #[test]
    fn test_query_with_variable() {
        let mut reasoner = SymbolicReasoner::new();

        // Facts
        reasoner.add_fact(Predicate {
            name: "is_a".to_string(),
            args: vec![
                Term::Constant("socrates".to_string()),
                Term::Constant("human".to_string()),
            ],
        });

        reasoner.add_fact(Predicate {
            name: "is_a".to_string(),
            args: vec![
                Term::Constant("plato".to_string()),
                Term::Constant("human".to_string()),
            ],
        });

        // Query: is_a(X, human) - find all humans
        let query = Predicate {
            name: "is_a".to_string(),
            args: vec![
                Term::Variable("X".to_string()),
                Term::Constant("human".to_string()),
            ],
        };

        let results = reasoner.query(&query);

        assert_eq!(results.len(), 2);
    }

    #[test]
    fn test_constraint_solver_basic() {
        let mut solver = ConstraintSolver::new();

        solver.add_constraint(Constraint::Equality(
            Term::Variable("X".to_string()),
            Term::Constant("5".to_string()),
        ));

        assert!(solver.is_satisfiable());
    }

    #[test]
    fn test_substitution_application() {
        let reasoner = SymbolicReasoner::new();

        let pred = Predicate {
            name: "likes".to_string(),
            args: vec![
                Term::Variable("X".to_string()),
                Term::Variable("Y".to_string()),
            ],
        };

        let mut sub = Substitution::new();
        sub.insert("X".to_string(), Term::Constant("alice".to_string()));
        sub.insert("Y".to_string(), Term::Constant("bob".to_string()));

        let result = reasoner.apply_substitution(&pred, &sub);

        assert_eq!(result.name, "likes");
        assert_eq!(result.args[0], Term::Constant("alice".to_string()));
        assert_eq!(result.args[1], Term::Constant("bob".to_string()));
    }

    #[test]
    fn test_function_term() {
        let reasoner = SymbolicReasoner::new();

        let t1 = Term::Function(
            "father".to_string(),
            vec![Term::Constant("alice".to_string())],
        );

        let t2 = Term::Function(
            "father".to_string(),
            vec![Term::Constant("alice".to_string())],
        );

        let mut sub = HashMap::new();
        assert!(reasoner.unify_terms(&t1, &t2, &mut sub));
    }

    #[test]
    fn test_complex_rule_chain() {
        let mut reasoner = SymbolicReasoner::new();

        // Facts: parent relationships
        reasoner.add_fact(Predicate {
            name: "parent".to_string(),
            args: vec![
                Term::Constant("john".to_string()),
                Term::Constant("mary".to_string()),
            ],
        });

        reasoner.add_fact(Predicate {
            name: "parent".to_string(),
            args: vec![
                Term::Constant("mary".to_string()),
                Term::Constant("alice".to_string()),
            ],
        });

        // Rule: parent(X, Y) ∧ parent(Y, Z) → grandparent(X, Z)
        reasoner.add_rule(LogicRule {
            premises: vec![
                Predicate {
                    name: "parent".to_string(),
                    args: vec![
                        Term::Variable("X".to_string()),
                        Term::Variable("Y".to_string()),
                    ],
                },
                Predicate {
                    name: "parent".to_string(),
                    args: vec![
                        Term::Variable("Y".to_string()),
                        Term::Variable("Z".to_string()),
                    ],
                },
            ],
            conclusion: Predicate {
                name: "grandparent".to_string(),
                args: vec![
                    Term::Variable("X".to_string()),
                    Term::Variable("Z".to_string()),
                ],
            },
            confidence: 1.0,
        });

        let derived = reasoner.forward_chain(10);

        // Should derive grandparent(john, alice)
        assert!(reasoner.facts.contains(&Predicate {
            name: "grandparent".to_string(),
            args: vec![
                Term::Constant("john".to_string()),
                Term::Constant("alice".to_string())
            ],
        }));
    }

    #[test]
    fn test_no_infinite_loop_backward_chain() {
        let mut reasoner = SymbolicReasoner::new();

        // Self-referential rule (potential infinite loop)
        reasoner.add_rule(LogicRule {
            premises: vec![Predicate {
                name: "loop".to_string(),
                args: vec![Term::Variable("X".to_string())],
            }],
            conclusion: Predicate {
                name: "loop".to_string(),
                args: vec![Term::Variable("X".to_string())],
            },
            confidence: 1.0,
        });

        let goal = Predicate {
            name: "loop".to_string(),
            args: vec![Term::Constant("test".to_string())],
        };

        // Should terminate without infinite loop
        let result = reasoner.backward_chain(&goal);
        assert!(!result); // Should not prove without base facts
    }

    #[test]
    fn test_consistency_check() {
        let reasoner = SymbolicReasoner::new();
        assert!(reasoner.is_consistent());
    }
}
