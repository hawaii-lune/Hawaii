-- experiment tests using PackageIO to pack a single HelloWorld.luau
-- file with a dependency reference to Hawaii.System (not a real package)

function exports.main()
	print("Hello World!")
end