import UIKit

/// Wrapping, removable tag chips with a bounded scroll area, shared by the
/// compact profile search header and its separate tag editor.
final class ProfileTagChips: UIView {
    var onAdd: (() -> Void)?, onRemove: ((String) -> Void)?
    private let scroll = UIScrollView()
    private var buttons = [UIButton](), values = [String](), showsAdd = true
    private var measuredWidth: CGFloat = 0
    override init(frame: CGRect = .zero) {
        super.init(frame: frame); addSubview(scroll); scroll.showsVerticalScrollIndicator = false
        setContentCompressionResistancePriority(.required, for: .vertical)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func show(_ tags: [String], add: Bool = true) {
        guard values != tags || showsAdd != add || buttons.isEmpty else { return }
        values = tags; showsAdd = add; buttons.forEach { $0.removeFromSuperview() }; buttons = []
        for tag in tags {
            let button = UIButton(type: .custom)
            button.setTitle("#" + tag + "  ×", for: .normal); button.setTitleColor(ClassicTheme.yellow, for: .normal)
            button.backgroundColor = ClassicTheme.drawer; button.layer.cornerRadius = 3
            button.titleLabel?.lineBreakMode = .byTruncatingTail; button.titleLabel?.font = ClassicTheme.font(14)
            button.accessibilityLabel = "Remove tag " + tag
            button.addAction(UIAction { [weak self] _ in self?.onRemove?(tag) }, for: .touchUpInside)
            buttons.append(button); scroll.addSubview(button)
        }
        if add {
            let button = UIButton(type: .custom)
            button.setTitle(tags.isEmpty ? "Search #tags" : "+ Add tags", for: .normal)
            button.setTitleColor(tags.isEmpty ? ClassicTheme.muted : ClassicTheme.text, for: .normal)
            button.titleLabel?.font = ClassicTheme.font(14); button.accessibilityLabel = "Add tags"
            button.addAction(UIAction { [weak self] _ in self?.onAdd?() }, for: .touchUpInside)
            buttons.append(button); scroll.addSubview(button)
        }
        invalidateIntrinsicContentSize(); setNeedsLayout()
    }
    private func arrange(width: CGFloat, layout: Bool) -> CGFloat {
        let available = max(1, width - 8)
        var x: CGFloat = 4, y: CGFloat = 4
        for button in buttons {
            let w = min(available, max(44, button.sizeThatFits(CGSize(width: available, height: 32)).width + 16))
            if x > 4 && x + w > width - 4 { x = 4; y += 36 }
            if layout { button.frame = CGRect(x: x, y: y, width: w, height: 32) }
            x += w + 6
        }
        return buttons.isEmpty ? 0 : y + 36
    }
    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: min(144, max(44, arrange(width: bounds.width > 0 ? bounds.width : 320, layout: false))))
    }
    override func layoutSubviews() {
        super.layoutSubviews(); scroll.frame = bounds
        scroll.contentSize = CGSize(width: bounds.width, height: arrange(width: bounds.width, layout: true))
        if measuredWidth != bounds.width { measuredWidth = bounds.width; invalidateIntrinsicContentSize() }
    }
}

final class ProfileTagEditor: ClassicScreenController, UITextFieldDelegate, UITableViewDataSource, UITableViewDelegate {
    private let app: AppContext, completion: ([String]) -> Void
    private var selection: ProfileTagSelection
    private let chips = ProfileTagChips(), input = ClassicTextField(), counter = UILabel()
    private let table = UITableView(frame: .zero, style: .plain), status = StatusView()
    private var suggestions = [String](), pendingRecents = [String](), generation = UUID()
    private var task: Task<Void, Never>?, committed = false, observer: NSObjectProtocol?
    private let recentKey = "oldFunny.profileTagRecents.v1"
    init(app: AppContext, tags: [String], completion: @escaping ([String]) -> Void) {
        self.app = app; selection = ProfileTagSelection(tags); self.completion = completion
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { task?.cancel(); if let observer { NotificationCenter.default.removeObserver(observer) } }
    override func viewDidLoad() {
        super.viewDidLoad(); view.accessibilityIdentifier = "profile-tag-editor"; classicBar.setTitle("Search tags")
        classicBar.onLeading = { [weak self] in self?.finish() }
        classicBar.trailing.setImage(UIImage(systemName: "trash"), for: .normal); classicBar.trailing.accessibilityLabel = "Clear recent tags"
        classicBar.onTrailing = { [weak self] in
            guard let self else { return }; UserDefaults.standard.removeObject(forKey: recentKey); pendingRecents = []; queryChanged()
        }
        chips.onRemove = { [weak self] tag in self?.selection.remove(tag); self?.renderSelection() }
        input.textColor = ClassicTheme.text; input.backgroundColor = ClassicTheme.drawer; input.font = ClassicTheme.font(16)
        input.attributedPlaceholder = NSAttributedString(string: "Search #tags", attributes: [.foregroundColor: ClassicTheme.muted])
        input.accessibilityIdentifier = "profile-tag-input"; input.autocapitalizationType = .none; input.autocorrectionType = .no
        input.returnKeyType = .done; input.delegate = self; input.addTarget(self, action: #selector(queryChanged), for: .editingChanged)
        input.heightAnchor.constraint(equalToConstant: 40).isActive = true
        counter.font = ClassicTheme.font(14); counter.textColor = ClassicTheme.muted; counter.accessibilityIdentifier = "profile-tags-remaining"
        let fields = UIStackView(arrangedSubviews: [chips, input, counter]); fields.axis = .vertical; fields.spacing = 6
        fields.isLayoutMarginsRelativeArrangement = true; fields.layoutMargins = UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 12); fields.backgroundColor = ClassicTheme.bar
        table.backgroundColor = ClassicTheme.background; table.separatorColor = ClassicTheme.drawer; table.rowHeight = 48
        table.dataSource = self; table.delegate = self; table.keyboardDismissMode = .onDrag
        table.accessibilityIdentifier = "profile-tag-suggestions"
        for item in [fields, table, status] { item.translatesAutoresizingMaskIntoConstraints = false; contentView.addSubview(item) }
        NSLayoutConstraint.activate([
            fields.topAnchor.constraint(equalTo: contentView.topAnchor), fields.leadingAnchor.constraint(equalTo: contentView.leadingAnchor), fields.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            table.topAnchor.constraint(equalTo: fields.bottomAnchor), table.leadingAnchor.constraint(equalTo: contentView.leadingAnchor), table.trailingAnchor.constraint(equalTo: contentView.trailingAnchor), table.bottomAnchor.constraint(equalTo: contentView.keyboardLayoutGuide.topAnchor),
            status.topAnchor.constraint(equalTo: table.topAnchor), status.leadingAnchor.constraint(equalTo: table.leadingAnchor), status.trailingAnchor.constraint(equalTo: table.trailingAnchor), status.bottomAnchor.constraint(equalTo: table.bottomAnchor)
        ])
        status.retry.addTarget(self, action: #selector(queryChanged), for: .touchUpInside)
        observer = NotificationCenter.default.addObserver(forName: .oldFunnyAccountChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in guard let self else { return }; self.task?.cancel(); self.generation = UUID(); self.committed = true; self.navigationController?.popViewController(animated: true) }
        }
        renderSelection(); queryChanged()
    }
    override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); input.becomeFirstResponder() }
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isMovingFromParent || navigationController == nil { commit() }
    }
    private func renderSelection() {
        chips.show(selection.tags, add: false)
        counter.text = "\(ProfileTagSelection.limit - selection.tags.count)"
        counter.accessibilityLabel = "\(ProfileTagSelection.limit - selection.tags.count) tags remaining"
        counter.textColor = selection.tags.count == ProfileTagSelection.limit ? .systemRed : ClassicTheme.muted
    }
    @objc private func queryChanged() {
        task?.cancel(); generation = UUID(); suggestions = []
        let text = ProfileSearchCriteria.normalized(input.text ?? "")
        if text.isEmpty {
            suggestions = (UserDefaults.standard.stringArray(forKey: recentKey) ?? []).filter { ProfileTagSelection.valid($0) != nil }
            table.reloadData(); status.isHidden = true; return
        }
        guard text.utf16.count > 1 else { table.reloadData(); status.isHidden = true; return }
        status.loading(); let owner = generation
        task = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(nanoseconds: 250_000_000); try Task.checkCancellation()
                let result = try await app.api.suggestedTags(text)
                try Task.checkCancellation(); guard owner == generation else { return }
                suggestions = result.tags; table.reloadData(); status.isHidden = true
            } catch is CancellationError {} catch {
                guard owner == generation else { return }; status.message("Could not load tag suggestions.")
            }
        }
    }
    private func add(_ tag: String) {
        guard selection.add(tag) else { return }
        let value = ProfileSearchCriteria.normalized(tag)
        pendingRecents.removeAll { $0 == value }; pendingRecents.insert(value, at: 0)
        input.text = ""; renderSelection(); queryChanged()
    }
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        guard textField.markedTextRange == nil, let current = textField.text, let swiftRange = Range(range, in: current) else { return true }
        let next = current.replacingCharacters(in: swiftRange, with: string)
        guard string.contains(where: { $0.isWhitespace }) else { return next.utf16.count <= 100 }
        let parts = next.components(separatedBy: .whitespacesAndNewlines)
        for tag in parts.dropLast() where !tag.isEmpty { add(tag) }
        input.text = parts.last ?? ""; queryChanged(); return false
    }
    func textFieldShouldReturn(_ textField: UITextField) -> Bool { add(input.text ?? ""); return true }
    private func commit() {
        guard !committed else { return }; committed = true; task?.cancel(); generation = UUID()
        let pending = input.text ?? ""; if !pending.isEmpty { _ = selection.add(pending) }
        var recent = pendingRecents + (UserDefaults.standard.stringArray(forKey: recentKey) ?? [])
        if let value = ProfileTagSelection.valid(pending), selection.tags.contains(value) { recent.insert(value, at: 0) }
        var seen = Set<String>(); recent = recent.filter { seen.insert($0).inserted }
        UserDefaults.standard.set(Array(recent.prefix(10)), forKey: recentKey)
        completion(selection.tags)
    }
    private func finish() { commit(); view.endEditing(true); navigationController?.popViewController(animated: true) }
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { suggestions.count }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "tag") ?? UITableViewCell(style: .default, reuseIdentifier: "tag")
        let value = suggestions[indexPath.row]; cell.textLabel?.text = "#" + value
        cell.backgroundColor = ClassicTheme.background; cell.textLabel?.textColor = ClassicTheme.yellow; cell.textLabel?.font = ClassicTheme.font(16)
        cell.accessibilityIdentifier = "suggested-tag-" + value; return cell
    }
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) { tableView.deselectRow(at: indexPath, animated: true); add(suggestions[indexPath.row]) }
}
