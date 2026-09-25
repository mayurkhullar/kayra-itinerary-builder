import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../clients/data/client_repository.dart';
import '../../../clients/domain/kayra_client.dart';
import '../../../users/domain/kayra_user.dart';
import '../../domain/kayra_trip.dart';
import 'my_trips_list.dart';
import 'trip_client_selector.dart';

class CreateTripForm extends StatefulWidget {
  const CreateTripForm({
    super.key,
    required this.currentUser,
    required this.clientRepository,
    required this.onCreate,
    required this.onClients,
  });
  final KayraUser currentUser;
  final ClientRepository clientRepository;
  final Future<void> Function(KayraClient client, TripBrief brief) onCreate;
  final VoidCallback onClients;
  @override
  State<CreateTripForm> createState() => _CreateTripFormState();
}

class _CreateTripFormState extends State<CreateTripForm> {
  final _form = GlobalKey<FormState>();
  final _destination = TextEditingController();
  final _destinationField = GlobalKey<FormFieldState<List<String>>>();
  final _dateField = GlobalKey<FormFieldState<DateTime>>();
  final _dateText = TextEditingController();
  final _numbers = {
    'Number of Nights': TextEditingController(text: '1'),
    'Adults': TextEditingController(text: '1'),
    'Children': TextEditingController(text: '0'),
    'Infants': TextEditingController(text: '0'),
  };
  final _destinations = <String>[];
  List<KayraClient>? _clients;
  KayraClient? _client;
  DateTime? _date;
  HotelCategory? _hotel;
  TripType? _type;
  bool _loadingFailed = false;
  bool _saving = false;
  bool _saveFailed = false;
  DialogRoute<DateTime>? _dateRoute;

  @override
  void initState() {
    super.initState();
    _loadClients();
  }

  @override
  void dispose() {
    _destination.dispose();
    _dateText.dispose();
    for (final controller in _numbers.values) {
      controller.dispose();
    }
    final route = _dateRoute;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (route != null && route.isActive) route.navigator?.removeRoute(route);
    });
    super.dispose();
  }

  Future<void> _loadClients() async {
    setState(() {
      _loadingFailed = false;
      _clients = null;
    });
    try {
      final clients = widget.currentUser.isActiveAdmin
          ? await widget.clientRepository.listAllClientsForAdmin()
          : await widget.clientRepository.listOwnedClients(
              widget.currentUser.uid,
            );
      if (!mounted) return;
      final sorted = List<KayraClient>.of(clients)
        ..sort(
          (a, b) => a.displayName.toLowerCase().compareTo(
            b.displayName.toLowerCase(),
          ),
        );
      setState(() => _clients = sorted);
    } catch (_) {
      if (mounted) setState(() => _loadingFailed = true);
    }
  }

  String? _numberError(String label, String? text) {
    final value = int.tryParse(text?.trim() ?? '');
    if (value == null) return 'Enter a whole number.';
    try {
      TripValidation.count(
        value,
        label,
        minimum: label == 'Adults' || label == 'Number of Nights' ? 1 : 0,
      );
      return null;
    } on FormatException catch (error) {
      return error.message;
    }
  }

  String? _companyError() {
    if (_type == null || _client == null) return null;
    try {
      TripValidation.clientCompany(_type!, _client!.company);
      return null;
    } on FormatException {
      return 'Add a company to this Client before creating a ${_type!.label} trip.';
    }
  }

  TripBrief _brief() => TripBrief(
    destinations: _destinations,
    travelStartDate: _date!,
    numberOfNights: int.parse(_numbers['Number of Nights']!.text.trim()),
    adults: int.parse(_numbers['Adults']!.text.trim()),
    children: int.parse(_numbers['Children']!.text.trim()),
    infants: int.parse(_numbers['Infants']!.text.trim()),
    hotelCategory: _hotel!,
    tripType: _type!,
  );
  String? get _preview {
    if (_client == null || _date == null) {
      return null;
    }
    try {
      return TripBrief.generateName(
        firstName: _client!.firstName,
        lastName: _client!.lastName,
        destinations: _destinations,
        travelStartDate: _date!,
      );
    } on FormatException {
      return null;
    }
  }

  void _addDestination() {
    final text = _destination.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _destinations.add(text);
      _destination.clear();
    });
    _destinationField.currentState?.didChange(List.of(_destinations));
  }

  Future<void> _pickDate() async {
    if (_saving || _dateRoute != null) return;
    final route = DialogRoute<DateTime>(
      context: context,
      builder: (_) => DatePickerDialog(
        initialDate: _date ?? DateTime.now(),
        firstDate: DateTime(2000),
        lastDate: DateTime(2100, 12, 31),
      ),
    );
    _dateRoute = route;
    final selected = await Navigator.of(context).push(route);
    _dateRoute = null;
    if (mounted && selected != null) {
      setState(() {
        _date = selected;
        _dateText.text = tripDateLabel(selected);
      });
      _dateField.currentState?.didChange(selected);
    }
  }

  Future<void> _save() async {
    if (_saving || _clients == null || _clients!.isEmpty) return;
    _addDestination();
    final invalid = _form.currentState!.validateGranularly();
    if (invalid.isNotEmpty) {
      await Scrollable.ensureVisible(
        invalid.first.context,
        alignment: 0.1,
        duration: const Duration(milliseconds: 200),
      );
      return;
    }
    final brief = _brief();
    brief.validateClientCompany(_client!.company);
    setState(() {
      _saving = true;
      _saveFailed = false;
    });
    try {
      await widget.onCreate(_client!, brief);
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _saveFailed = true;
        });
      }
    }
  }

  Widget _number(String label) => TextFormField(
    key: ValueKey('trip-$label'),
    controller: _numbers[label],
    enabled: !_saving,
    keyboardType: const TextInputType.numberWithOptions(signed: true),
    decoration: InputDecoration(
      labelText: label == 'Number of Nights' ? '$label *' : label,
      errorMaxLines: 3,
    ),
    validator: (text) => _numberError(label, text),
    onChanged: (_) => setState(() {}),
    autovalidateMode: AutovalidateMode.onUserInteraction,
  );
  Widget _row(List<Widget> children, bool wide) => wide
      ? Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(width: 16),
              Expanded(child: children[i]),
            ],
          ],
        )
      : Column(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(height: 16),
              children[i],
            ],
          ],
        );

  Widget _fields(bool wide) => Form(
    key: _form,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TripClientSelector(
          clients: _clients!,
          enabled: !_saving,
          onChanged: (client) => setState(() => _client = client),
        ),
        const SizedBox(height: 20),
        FormField<List<String>>(
          key: _destinationField,
          initialValue: const [],
          validator: (_) {
            try {
              TripValidation.destinations(_destinations);
              return null;
            } on FormatException catch (error) {
              return error.message;
            }
          },
          builder: (field) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const ValueKey('trip-destination'),
                controller: _destination,
                enabled: !_saving,
                onSubmitted: (_) => _addDestination(),
                decoration: InputDecoration(
                  labelText: 'Destinations *',
                  hintText: 'Enter a destination',
                  errorText: field.errorText,
                  errorMaxLines: 2,
                  suffixIcon: TextButton(
                    onPressed: _saving ? null : _addDestination,
                    child: const Text('Add'),
                  ),
                ),
              ),
              if (_destinations.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (var i = 0; i < _destinations.length; i++)
                      InputChip(
                        label: Text(_destinations[i], softWrap: true),
                        onDeleted: _saving
                            ? null
                            : () {
                                setState(() => _destinations.removeAt(i));
                                field.didChange(List.of(_destinations));
                              },
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 20),
        _row([
          FormField<DateTime>(
            key: _dateField,
            validator: (value) =>
                value == null ? 'Select a travel date.' : null,
            builder: (field) => TextField(
              key: const ValueKey('trip-date'),
              controller: _dateText,
              readOnly: true,
              enabled: !_saving,
              onTap: _pickDate,
              decoration: InputDecoration(
                labelText: 'Travel Date *',
                suffixIcon: const Icon(Icons.calendar_today_outlined, size: 20),
                errorText: field.errorText,
              ),
            ),
          ),
          _number('Number of Nights'),
        ], wide),
        const SizedBox(height: 20),
        _row([
          _number('Adults'),
          _number('Children'),
          _number('Infants'),
        ], wide),
        const SizedBox(height: 20),
        _row([
          DropdownButtonFormField<HotelCategory>(
            key: const ValueKey('trip-hotel'),
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Hotel Category *'),
            items: [
              for (final value in HotelCategory.values)
                DropdownMenuItem(value: value, child: Text(value.label)),
            ],
            onChanged: _saving
                ? null
                : (value) => setState(() => _hotel = value),
            validator: (value) =>
                value == null ? 'Select a hotel category.' : null,
          ),
          DropdownButtonFormField<TripType>(
            key: const ValueKey('trip-type'),
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Trip Type *',
              errorMaxLines: 4,
            ),
            items: [
              for (final value in TripType.values)
                DropdownMenuItem(value: value, child: Text(value.label)),
            ],
            onChanged: _saving
                ? null
                : (value) => setState(() => _type = value),
            validator: (value) =>
                value == null ? 'Select a trip type.' : _companyError(),
            autovalidateMode: AutovalidateMode.onUserInteraction,
          ),
        ], wide),
        if (_preview != null) ...[
          const SizedBox(height: 20),
          Text('Trip name', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 4),
          Text(
            _preview!,
            key: const ValueKey('trip-name-preview'),
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ],
        if (_saveFailed) ...[
          const SizedBox(height: 16),
          Semantics(
            liveRegion: true,
            child: const Text(
              'Itinerary couldn’t be created. Please try again.',
            ),
          ),
        ],
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final wide =
          constraints.maxWidth >= 720 &&
          MediaQuery.textScalerOf(context).scale(16) <= 20;
      final Widget content;
      if (_loadingFailed) {
        content = Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Client data couldn’t be loaded.'),
            TextButton(onPressed: _loadClients, child: const Text('Try again')),
          ],
        );
      } else if (_clients == null) {
        content = const Padding(
          padding: EdgeInsets.all(24),
          child: Center(
            child: SizedBox.square(
              dimension: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                semanticsLabel: 'Loading clients',
              ),
            ),
          ),
        );
      } else if (_clients!.isEmpty) {
        content = Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'No clients available',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              'Create a client before starting a new itinerary.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: widget.onClients,
              child: const Text('Go to Clients'),
            ),
          ],
        );
      } else {
        content = _fields(wide);
      }
      return PopScope(
        canPop: !_saving,
        child: AlertDialog(
          backgroundColor: AppColors.white,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          insetPadding: const EdgeInsets.all(20),
          contentPadding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.r12),
            side: const BorderSide(color: AppColors.border),
          ),
          scrollable: true,
          title: const Text('Create New Itinerary'),
          content: SizedBox(width: 680, child: content),
          actions: [
            TextButton(
              onPressed: _saving
                  ? null
                  : () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: _saving || _clients == null || _clients!.isEmpty
                  ? null
                  : _save,
              child: _saving
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        semanticsLabel: 'Creating itinerary',
                      ),
                    )
                  : const Text('Create Itinerary'),
            ),
          ],
        ),
      );
    },
  );
}
